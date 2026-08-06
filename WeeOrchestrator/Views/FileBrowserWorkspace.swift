import SwiftUI
import WebKit

/// Pure path arithmetic for the file browser, kept separate from
/// FileBrowserController so it's unit-testable without a network mock (this
/// codebase has no existing infrastructure for mocking WeeAPIClient's calls
/// -- see the same tradeoff noted for issue #65's memories section).
enum FileBrowserPath {
    static func components(for path: String) -> [String] {
        path.isEmpty ? [] : path.split(separator: "/").map(String.init)
    }

    static func parent(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    static func joined(_ base: String, _ name: String) -> String {
        base.isEmpty ? name : "\(base)/\(name)"
    }

    static func breadcrumbTarget(from path: String, upTo index: Int) -> String {
        components(for: path).prefix(index + 1).joined(separator: "/")
    }

    /// Builds the full host path GET /api/v1/files/view expects (it
    /// validates against a broader, non-agent-scoped allowlist than the
    /// per-agent listing endpoint) from the agent's root + a relative path.
    static func absolute(root: String, relative: String) -> String {
        root.hasSuffix("/") ? root + relative : root + "/" + relative
    }
}

/// Per-session file browser (issue #62): lists files under the current
/// agent's working folder via GET /api/v1/agents/{name}/files (server-side
/// path-traversal guard, scoped to that agent's own root -- see the
/// endpoint's docstring in agent_manager.py) and previews supported formats
/// via the existing GET /api/v1/files/view.
@MainActor
@Observable
final class FileBrowserController {
    private let client: WeeAPIClient
    let agentName: String

    private(set) var currentPath = ""
    private(set) var entries: [AgentFileEntry] = []
    private(set) var isLoadingList = false
    private(set) var listError: String?

    private(set) var selectedFile: AgentFileEntry?
    private(set) var fileContent: FileViewResponse?
    private(set) var isLoadingContent = false
    private(set) var isBinaryOrUnsupported = false
    private(set) var contentError: String?

    /// The agent's absolute working directory, needed to build the full
    /// host path /api/v1/files/view expects (it validates against a
    /// broader, non-agent-scoped allowlist than the listing endpoint).
    private let agentRootPath: String

    init(client: WeeAPIClient, agentName: String, agentRootPath: String) {
        self.client = client
        self.agentName = agentName
        self.agentRootPath = agentRootPath
    }

    var canGoUp: Bool { currentPath.isEmpty == false }

    var breadcrumbComponents: [String] {
        FileBrowserPath.components(for: currentPath)
    }

    func loadRoot() async {
        await load(path: "")
    }

    func load(path: String) async {
        isLoadingList = true
        listError = nil
        selectedFile = nil
        fileContent = nil
        contentError = nil
        defer { isLoadingList = false }
        do {
            let response = try await client.agentFiles(agent: agentName, path: path)
            currentPath = response.path
            entries = response.entries
        } catch {
            listError = "Could not load files: \(error.localizedDescription)"
        }
    }

    func goUp() async {
        guard canGoUp else { return }
        await load(path: FileBrowserPath.parent(of: currentPath))
    }

    func goToBreadcrumb(index: Int) async {
        await load(path: FileBrowserPath.breadcrumbTarget(from: currentPath, upTo: index))
    }

    func select(_ entry: AgentFileEntry) async {
        if entry.isDirectory {
            await load(path: FileBrowserPath.joined(currentPath, entry.name))
            return
        }

        selectedFile = entry
        isLoadingContent = true
        isBinaryOrUnsupported = false
        contentError = nil
        fileContent = nil
        defer { isLoadingContent = false }

        let relative = FileBrowserPath.joined(currentPath, entry.name)
        let absolute = FileBrowserPath.absolute(root: agentRootPath, relative: relative)
        do {
            fileContent = try await client.viewFile(absolutePath: absolute)
        } catch is DecodingError {
            // /api/v1/files/view returns raw bytes, not this model's JSON
            // shape, for binary extensions -- a decode failure (not an
            // WeeAPIError, since the HTTP call itself succeeded) is the
            // signal to fall back to "preview not supported" rather than
            // surfacing a decode error to the user.
            isBinaryOrUnsupported = true
        } catch {
            contentError = "Could not open \(entry.name): \(error.localizedDescription)"
        }
    }

    func deselectFile() {
        selectedFile = nil
        fileContent = nil
        contentError = nil
        isBinaryOrUnsupported = false
    }
}

struct FileBrowserPanel: View {
    @Bindable var controller: FileBrowserController
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(WeeTheme.divider)

            if let file = controller.selectedFile {
                filePreview(file)
            } else {
                fileList
            }
        }
        .background(WeeTheme.background)
        .task { await controller.loadRoot() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            HStack(spacing: 7) {
                if controller.selectedFile != nil {
                    Button { controller.deselectFile() } label: { Image(systemName: "chevron.left") }
                        .help("Back to file list")
                } else {
                    Button { Task { await controller.goUp() } } label: { Image(systemName: "arrow.up") }
                        .disabled(!controller.canGoUp)
                        .help("Up one level")
                }

                Text(controller.selectedFile?.name ?? "Files")
                    .weeFont(.caption, weight: .semibold)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button { isVisible = false } label: { Image(systemName: "sidebar.trailing") }
                    .help("Hide file browser")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(WeeTheme.textSecondary)

            if controller.selectedFile == nil {
                breadcrumbBar
            }
        }
        .padding(8)
        .background(WeeTheme.sidebar)
    }

    @ViewBuilder
    private var breadcrumbBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                Button { Task { await controller.loadRoot() } } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.currentPath.isEmpty ? WeeTheme.accent : WeeTheme.textSecondary)

                ForEach(Array(controller.breadcrumbComponents.enumerated()), id: \.offset) { index, component in
                    Text("/").foregroundStyle(WeeTheme.textMuted)
                    Button(component) { Task { await controller.goToBreadcrumb(index: index) } }
                        .buttonStyle(.plain)
                        .foregroundStyle(index == controller.breadcrumbComponents.count - 1 ? WeeTheme.accent : WeeTheme.textSecondary)
                }
            }
            .weeFont(.caption2, weight: .medium)
        }
        .scrollIndicators(.hidden)
    }

    private var fileList: some View {
        Group {
            if controller.isLoadingList {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let listError = controller.listError {
                emptyState(symbol: "exclamationmark.triangle", text: listError, isError: true)
            } else if controller.entries.isEmpty {
                emptyState(symbol: "folder", text: "This folder is empty.", isError: false)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(controller.entries) { entry in
                            fileRow(entry)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fileRow(_ entry: AgentFileEntry) -> some View {
        Button {
            Task { await controller.select(entry) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.name))
                    .foregroundStyle(entry.isDirectory ? WeeTheme.accent : WeeTheme.textSecondary)
                    .frame(width: 16)
                Text(entry.name)
                    .weeFont(.caption)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let size = entry.size {
                    Text(formattedSize(size))
                        .weeFont(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isDirectory ? "Folder \(entry.name)" : "File \(entry.name)")
    }

    @ViewBuilder
    private func filePreview(_ entry: AgentFileEntry) -> some View {
        if controller.isLoadingContent {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let contentError = controller.contentError {
            emptyState(symbol: "exclamationmark.triangle", text: contentError, isError: true)
        } else if controller.isBinaryOrUnsupported {
            emptyState(
                symbol: "doc.questionmark",
                text: "Preview not available for this file type in-app.\n\(entry.name)",
                isError: false
            )
        } else if let file = controller.fileContent {
            filePreviewContent(file)
        }
    }

    @ViewBuilder
    private func filePreviewContent(_ file: FileViewResponse) -> some View {
        switch file.language {
        case "markdown":
            ScrollView {
                MarkdownText(file.content)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "html":
            // Sandboxed: no JavaScript, no persistent data store, no
            // baseURL -- so relative references can't reach local files --
            // satisfying issue #62's "without arbitrary local-file or
            // privileged-script access."
            SandboxedHTMLPreview(html: file.content)
        default:
            ScrollView {
                Text(file.content)
                    .weeFont(.caption, design: .monospaced)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
    }

    private func emptyState(symbol: String, text: String, isError: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .weeFont(size: 22)
                .foregroundStyle(isError ? WeeTheme.danger : WeeTheme.textMuted)
            Text(text)
                .weeFont(.caption)
                .foregroundStyle(WeeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func icon(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "md": return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp": return "photo"
        case "pdf": return "doc.fill"
        case "json", "yaml", "yml", "toml": return "curlybraces"
        case "py", "js", "ts", "tsx", "jsx", "go", "rs", "swift", "java", "rb", "php", "c", "cpp", "h": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    private func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Sandboxed HTML preview: no JavaScript, no persistent storage, no
/// baseURL. Separate from NativeWebView (the interactive Wee browser),
/// which deliberately allows JS for its own, different purpose.
private struct SandboxedHTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }
}

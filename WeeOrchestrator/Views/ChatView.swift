import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AVFoundation
import Observation
import WebKit

struct ChatView: View {
    @Bindable var model: WeeAppModel
    @State private var draft = ""
    @State private var isShowingHistory = false
    @State private var pendingAttachments: [ChatAttachment] = []
    @State private var isDropTargeted = false
    @State private var isShowingFilePicker = false
    @State private var voice = ChatVoiceController()

    var body: some View {
        VStack(spacing: 0) {
            HeaderPanel(model: model, isShowingHistory: $isShowingHistory)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            HStack(spacing: 8) {
                RecentChatsRail(model: model, layout: .vertical)
                    .frame(width: 220)

                chatTranscript
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            inputBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .onDrop(of: [.fileURL, .image, .png, .jpeg, .tiff, .pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(WeeTheme.accent, lineWidth: 3)
                    .background(WeeTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .weeFont(.largeTitle)
                            Text("Drop files here")
                                .weeFont(.headline)
                        }
                        .foregroundStyle(WeeTheme.accent)
                    }
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $isShowingHistory) {
            SessionHistorySheet(model: model, isPresented: $isShowingHistory)
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.image, .png, .jpeg, .tiff, .pdf, .plainText, .json, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                for url in urls {
                    addAttachment(from: url)
                }
            }
        }
        .onDisappear { voice.cancelAll() }
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.isShowingRecentChatWindow {
                        Text("Showing the most recent \(model.chatMessages.count) messages")
                            .font(.caption)
                            .foregroundStyle(WeeTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    ForEach(model.chatMessages) { message in
                        if message.isContextBoundary {
                            ContextBoundaryBanner(text: message.text)
                                .id(message.id)
                        } else {
                            ChatBubble(
                                message: message,
                                isStreaming: isStreaming(message),
                                isPreparingSpeech: voice.loadingMessageID == message.id,
                                isSpeaking: voice.speakingMessageID == message.id,
                                userAvatarImage: model.userAvatarImage,
                                onSpeak: {
                                    Task { await voice.toggleSpeech(for: message, model: model) }
                                }
                            )
                                .id(message.id)
                        }
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
            .glassPanel()
            .onChange(of: model.chatMessages.count) {
                if let last = model.chatMessages.last {
                    withAnimation(.snappy) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func isStreaming(_ message: ChatMessage) -> Bool {
        model.isCurrentSessionStreaming
            && message.role == .assistant
            && model.chatMessages.last?.id == message.id
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !model.currentQueuedChatMessages.isEmpty {
                ChatQueuePanel(model: model) { item in
                    guard let queued = model.takeQueuedChatMessageForEditing(id: item.id) else { return }
                    draft = queued.text
                    pendingAttachments = queued.attachments
                }
            }

            if !pendingAttachments.isEmpty {
                attachmentPreview
            }

            if let voiceStatus = voice.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: voice.statusIsError ? "exclamationmark.triangle.fill" : "waveform")
                    Text(voiceStatus).lineLimit(1)
                    Spacer()
                }
                .weeFont(.caption, weight: .semibold)
                .foregroundStyle(voice.statusIsError ? WeeTheme.danger : WeeTheme.accent)
                .padding(.horizontal, 4)
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(spacing: 6) {
                    if let usage = model.sessionContextUsage {
                        ContextUsageRing(usage: usage)
                    }

                    Button {
                        isShowingFilePicker = true
                    } label: {
                        Image(systemName: "paperclip")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(WeeGhostButtonStyle())
                    .help("Attach file")
                }

                Button {
                    Task {
                        await voice.toggleRecording(model: model) { transcription in
                            let separator = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " "
                            draft += separator + transcription
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        if voice.isTranscribing {
                            ProgressView().controlSize(.mini).tint(WeeTheme.accent)
                        } else {
                            Image(systemName: voice.isRecording ? "stop.fill" : "mic.fill")
                        }
                        if voice.isRecording {
                            Text(voice.elapsedText)
                                .weeFont(.caption2, weight: .semibold).monospacedDigit()
                        }
                    }
                    .frame(minWidth: 20, minHeight: 20)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(voice.isTranscribing)
                .help(voice.isRecording ? "Stop and transcribe recording" : "Record voice message")

                ZStack(alignment: .topLeading) {
                    ChatComposerTextView(text: $draft, onSubmit: sendDraft)
                        .frame(minHeight: 40, maxHeight: 96)
                    if draft.isEmpty {
                        Text("Message Wee")
                            .foregroundStyle(WeeTheme.textMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 44, maxHeight: 100)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    sendDraft()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
                .help("Send message (Return; Shift-Return for a new line)")
            }
        }
        .padding(8)
        .glassPanel()
    }

    private var attachmentPreview: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pendingAttachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        if attachment.isImage, let img = attachment.nsImage {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "doc.fill")
                                    .weeFont(.title3)
                                Text(attachment.filename)
                                    .weeFont(.caption2)
                                    .lineLimit(1)
                            }
                            .foregroundStyle(WeeTheme.textSecondary)
                            .frame(width: 64, height: 64)
                            .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }

                        Button {
                            pendingAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .weeFont(.caption)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
        .frame(height: 72)
    }

    private func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !prompt.isEmpty || !attachments.isEmpty else { return }

        draft = ""
        pendingAttachments = []
        Task {
            if ChatComposerAction.action(for: prompt, attachments: attachments) == .cancel {
                await model.cancelCurrentChatRequest()
            } else {
                _ = await model.sendChat(prompt, attachments: attachments)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        addAttachment(from: url)
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { item, _ in
                    guard let image = item as? NSImage, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
                    let attachment = ChatAttachment(filename: "screenshot.png", data: pngData, mimeType: "image/png")
                    DispatchQueue.main.async {
                        pendingAttachments.append(attachment)
                    }
                }
            }
        }
    }

    private func addAttachment(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return }
        let filename = url.lastPathComponent
        let mime = mimeType(for: url)
        pendingAttachments.append(ChatAttachment(filename: filename, data: data, mimeType: mime))
    }

    private func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

// MARK: - Session-scoped native browser

struct ChatBrowserWorkspace: View {
    @Bindable var model: WeeAppModel
    let store: BrowserSessionStore
    @AppStorage("wee.browser.visible") private var browserVisible = true
    @State private var controller: BrowserSessionController?

    private var sessionKey: String {
        "\(model.activeEnvironment.rawValue):\(model.currentSessionID ?? "none")"
    }

    var body: some View {
        HSplitView {
            ChatView(model: model)
                .frame(minWidth: 520)

            if browserVisible {
                if let controller {
                    NativeBrowserPanel(controller: controller, isVisible: $browserVisible)
                        .frame(minWidth: 380, idealWidth: 620)
                } else {
                    browserPlaceholder
                        .frame(minWidth: 380, idealWidth: 620)
                }
            }
        }
        .overlay(alignment: .trailing) {
            if !browserVisible {
                Button {
                    browserVisible = true
                } label: {
                    Image(systemName: "globe")
                        .weeFont(size: 16, weight: .semibold)
                        .foregroundStyle(WeeTheme.accent)
                        .frame(width: 38, height: 48)
                        .background(
                            WeeTheme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(WeeTheme.glassStroke)
                        }
                }
                .buttonStyle(.plain)
                .help("Show session browser")
                .accessibilityLabel("Show Browser")
                .padding(.trailing, 8)
            }
        }
        .task(id: sessionKey) {
            guard let sessionID = model.currentSessionID else {
                controller = nil
                return
            }
            let selected = store.controller(
                environment: model.activeEnvironment,
                sessionID: sessionID,
                client: model.client
            )
            controller = selected
            selected.connect()
        }
    }

    private var browserPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .weeFont(size: 30)
                .foregroundStyle(WeeTheme.accent)
            Text("Session Browser")
                .weeFont(.headline, weight: .bold)
                .foregroundStyle(WeeTheme.textPrimary)
            Text("Send a message to create this chat session, then its private browser will appear here.")
                .weeFont(.caption)
                .foregroundStyle(WeeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WeeTheme.background)
    }
}

@MainActor
@Observable
final class BrowserSessionStore {
    private var controllers: [String: BrowserSessionController] = [:]

    func controller(
        environment: WeeEnvironment,
        sessionID: String,
        client: WeeAPIClient
    ) -> BrowserSessionController {
        let key = "\(environment.rawValue):\(sessionID)"
        if let existing = controllers[key] { return existing }
        let controller = BrowserSessionController(
            sessionKey: key,
            sessionID: sessionID,
            client: client
        )
        controllers[key] = controller
        return controller
    }
}

@MainActor
@Observable
final class BrowserSessionController: NSObject, WKNavigationDelegate {
    let sessionKey: String
    let sessionID: String
    let clientID = UUID().uuidString
    let webView: WKWebView
    var address = ""
    var title = "New Tab"
    var isLoading = false
    var bridgeStatus = "Connecting…"
    var lastError: String?

    private let client: WeeAPIClient
    @ObservationIgnored private var pollingTask: Task<Void, Never>?

    init(sessionKey: String, sessionID: String, client: WeeAPIClient) {
        self.sessionKey = sessionKey
        self.sessionID = sessionID
        self.client = client
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsMagnification = true
    }

    deinit { pollingTask?.cancel() }

    func connect() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollCommands()
        }
    }

    func navigate() {
        var value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value) else {
            lastError = "Invalid URL"
            return
        }
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        lastError = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        address = webView.url?.absoluteString ?? address
        title = webView.title?.isEmpty == false ? webView.title! : "Browser"
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        isLoading = false
        lastError = error.localizedDescription
    }

    private func pollCommands() async {
        do {
            try await client.registerNativeBrowser(sessionID: sessionID, clientID: clientID)
            bridgeStatus = "Wee connected"
        } catch {
            bridgeStatus = Self.bridgeStatus(for: error)
            lastError = bridgeStatus == "Reconnecting…" ? error.localizedDescription : nil
        }

        while !Task.isCancelled {
            do {
                let envelope = try await client.pollNativeBrowserCommand(
                    sessionID: sessionID,
                    clientID: clientID
                )
                bridgeStatus = "Wee connected"
                guard let command = envelope.command else { continue }
                let result = await execute(command)
                try await client.submitNativeBrowserResult(
                    sessionID: sessionID,
                    result: BrowserCommandResultRequest(
                        clientID: clientID,
                        commandID: command.id,
                        result: result.value,
                        error: result.error,
                        url: webView.url?.absoluteString,
                        title: webView.title
                    )
                )
            } catch is CancellationError {
                break
            } catch {
                bridgeStatus = Self.bridgeStatus(for: error)
                lastError = bridgeStatus == "Reconnecting…" ? error.localizedDescription : nil
                try? await Task.sleep(for: .seconds(2))
                try? await client.registerNativeBrowser(sessionID: sessionID, clientID: clientID)
            }
        }
    }

    static func bridgeStatus(for error: Error) -> String {
        if case WeeAPIError.httpStatus(let status, _) = error {
            if status == 404 { return "Server update required" }
            if status == 401 || status == 403 { return "Sign in required" }
        }
        return "Reconnecting…"
    }

    private func execute(_ command: BrowserCommand) async -> (value: String?, error: String?) {
        do {
            switch command.action.lowercased() {
            case "navigate":
                guard let target = command.url, !target.isEmpty else {
                    throw BrowserControlError("navigate requires url")
                }
                address = target
                navigate()
                try await Task.sleep(for: .milliseconds(900))
            case "click":
                let selector = javascriptLiteral(command.selector ?? "")
                let text = javascriptLiteral(command.text ?? "")
                let script = """
                (() => {
                  const selector = \(selector), text = \(text);
                  let el = selector ? document.querySelector(selector) : null;
                  if (!el && text) el = [...document.querySelectorAll('a,button,input,[role="button"]')].find(e => (e.innerText || e.value || '').includes(text));
                  if (!el) throw new Error('Element not found');
                  el.click();
                  return true;
                })()
                """
                _ = try await evaluate(script)
                try await Task.sleep(for: .milliseconds(500))
            case "type":
                guard let selector = command.selector, !selector.isEmpty else {
                    throw BrowserControlError("type requires selector")
                }
                let script = """
                (() => {
                  const el = document.querySelector(\(javascriptLiteral(selector)));
                  if (!el) throw new Error('Element not found');
                  el.focus(); el.value = \(javascriptLiteral(command.text ?? ""));
                  el.dispatchEvent(new Event('input', {bubbles:true}));
                  el.dispatchEvent(new Event('change', {bubbles:true}));
                  \((command.submit ?? false) ? "el.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', code:'Enter', bubbles:true})); if (el.form) el.form.requestSubmit();" : "")
                  return true;
                })()
                """
                _ = try await evaluate(script)
            case "evaluate":
                guard let script = command.script, !script.isEmpty else {
                    throw BrowserControlError("evaluate requires script")
                }
                let evaluated = try await evaluate(script)
                return (String(describing: evaluated ?? "null"), nil)
            case "back": goBack(); try await Task.sleep(for: .milliseconds(500))
            case "forward": goForward(); try await Task.sleep(for: .milliseconds(500))
            case "reload": reload(); try await Task.sleep(for: .milliseconds(700))
            case "snapshot": break
            default: throw BrowserControlError("Unknown browser action: \(command.action)")
            }
            return (try await snapshot(), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func snapshot() async throws -> String {
        let script = """
        JSON.stringify({
          url: location.href,
          title: document.title,
          text: (document.body?.innerText || '').slice(0, 12000),
          links: [...document.querySelectorAll('a')].slice(0, 50).map(a => ({text:(a.innerText || '').trim(), href:a.href}))
        })
        """
        return String(describing: try await evaluate(script) ?? "{}")
    }

    private func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: value) }
            }
        }
    }

    private func javascriptLiteral(_ value: String) -> String {
        let data = try? JSONEncoder().encode(value)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

private struct BrowserControlError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

private struct NativeBrowserPanel: View {
    @Bindable var controller: BrowserSessionController
    @Binding var isVisible: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Button(action: controller.goBack) { Image(systemName: "chevron.left") }
                    .disabled(!controller.webView.canGoBack)
                Button(action: controller.goForward) { Image(systemName: "chevron.right") }
                    .disabled(!controller.webView.canGoForward)
                Button(action: controller.reload) {
                    Image(systemName: controller.isLoading ? "xmark" : "arrow.clockwise")
                }

                TextField("Search or enter website", text: $controller.address)
                    .textFieldStyle(.plain)
                    .onSubmit { controller.navigate() }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(WeeTheme.glassStroke))

                Button { isVisible = false } label: { Image(systemName: "sidebar.trailing") }
                    .help("Hide browser")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(WeeTheme.textSecondary)
            .padding(8)
            .background(WeeTheme.sidebar)

            HStack {
                Image(systemName: "circle.fill")
                    .weeFont(size: 6)
                    .foregroundStyle(controller.bridgeStatus == "Wee connected" ? WeeTheme.emerald : WeeTheme.gold)
                Text(controller.title)
                    .weeFont(.caption, weight: .semibold)
                    .lineLimit(1)
                Spacer()
                Text(controller.bridgeStatus)
                    .weeFont(.caption2)
                    .foregroundStyle(WeeTheme.textMuted)
                Text(String(controller.sessionID.prefix(8)))
                    .weeFont(.caption2, design: .monospaced)
                    .foregroundStyle(WeeTheme.textMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(WeeTheme.surface)

            NativeWebView(webView: controller.webView)
                .id(controller.sessionKey)
                .overlay(alignment: .bottomLeading) {
                    if let error = controller.lastError {
                        Text(error)
                            .weeFont(.caption2)
                            .foregroundStyle(WeeTheme.danger)
                            .padding(7)
                            .background(WeeTheme.surfaceRaised.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
        }
        .background(WeeTheme.background)
        .overlay(alignment: .leading) { Rectangle().fill(WeeTheme.divider).frame(width: 1) }
    }
}

private struct NativeWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct ChatComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> ComposerNSTextView {
        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.string = text
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.focusRingType = .none
        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width, .height]
        return textView
    }

    func updateNSView(_ textView: ComposerNSTextView, context: Context) {
        textView.onSubmit = onSubmit
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private final class ComposerNSTextView: NSTextView {
    var onSubmit: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 36 || event.keyCode == 76 else {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.shift) || modifiers.contains(.option) {
            super.keyDown(with: event)
            return
        }

        let relevantModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if relevantModifiers.isEmpty || relevantModifiers == .command {
            onSubmit()
            return
        }

        super.keyDown(with: event)
    }
}

private struct ChatQueuePanel: View {
    @Bindable var model: WeeAppModel
    let onEdit: (QueuedChatMessage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .foregroundStyle(WeeTheme.accent)
                Text("Queued messages")
                    .weeFont(.caption, weight: .bold)
                    .foregroundStyle(WeeTheme.textPrimary)
                Text("\(model.currentChatQueueCount)")
                    .weeFont(.caption2, weight: .bold).monospacedDigit()
                    .foregroundStyle(WeeTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WeeTheme.accent.opacity(0.14), in: Capsule())
                Spacer()
                Button {
                    model.toggleChatQueuePause()
                } label: {
                    Label(
                        model.isChatQueuePaused ? "Resume" : "Pause",
                        systemImage: model.isChatQueuePaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            Text(model.isChatQueuePaused ? "Queue paused — resume to send the next message." : "Messages send automatically when the current response completes.")
                .weeFont(.caption2)
                .foregroundStyle(WeeTheme.textSecondary)

            ForEach(model.currentQueuedChatMessages) { item in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .weeFont(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                    Text(item.text.isEmpty ? "Attached \(item.attachments.count) file(s)" : item.text)
                        .weeFont(.caption)
                        .foregroundStyle(WeeTheme.textPrimary)
                        .lineLimit(1)
                    if !item.attachments.isEmpty {
                        Image(systemName: "paperclip")
                            .weeFont(.caption2)
                            .foregroundStyle(WeeTheme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Button("Edit") { onEdit(item) }
                        .buttonStyle(.plain)
                        .weeFont(.caption2, weight: .semibold)
                        .foregroundStyle(WeeTheme.accent)
                    Button("Cancel") {
                        model.removeQueuedChatMessage(id: item.id)
                    }
                    .buttonStyle(.plain)
                    .weeFont(.caption2, weight: .semibold)
                    .foregroundStyle(WeeTheme.danger)
                    .help("Cancel queued message")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(8)
        .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}

private struct HeaderPanel: View {
    @Bindable var model: WeeAppModel
    @Binding var isShowingHistory: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CHAT SESSION")
                    .weeFont(size: 9, weight: .bold)
                    .tracking(1)
                    .foregroundStyle(WeeTheme.textMuted)
                Text(model.currentSessionID ?? "New Session")
                    .weeFont(size: 15, weight: .bold)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 210, alignment: .leading)

            Divider().frame(height: 28).overlay(WeeTheme.divider)

            HStack(spacing: 6) {
                agentMenu
                runtimeMenu
                modelMenu
                fullAccessButton
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    Task { await model.startNewChat() }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .help("New Chat (⌘N)")

                Button {
                    isShowingHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .help("Chat History")

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(WeeTheme.accent)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .glassPanel()
    }

    private var environmentMenu: some View {
        Menu {
            ForEach(WeeEnvironment.allCases) { environment in
                Button {
                    Task { await model.switchEnvironment(to: environment) }
                } label: {
                    Label(environment.title, systemImage: environment == model.activeEnvironment ? "checkmark.circle.fill" : environment.symbol)
                }
            }
        } label: {
            HeaderChip(
                symbol: model.activeEnvironment.symbol,
                text: model.activeEnvironment.title,
                background: WeeTheme.accent.opacity(0.18),
                foreground: WeeTheme.accent,
                showsDisclosure: true
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isLoading)
    }

    private var agentMenu: some View {
        Menu {
            ForEach(model.agents) { agent in
                Button {
                    Task { await model.changeAgent(to: agent.name) }
                } label: {
                    Label(agent.name, systemImage: agent.name == model.selectedAgent ? "checkmark.circle.fill" : "person.crop.circle")
                }
            }
        } label: {
            HeaderChip(
                symbol: "person.crop.circle",
                text: model.selectedAgent,
                background: WeeTheme.gold,
                foreground: .black.opacity(0.82),
                showsDisclosure: true
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.agents.isEmpty || model.isLoading)
    }

    private var runtimeMenu: some View {
        Menu {
            Section("Switch Runtime") {
                ForEach(model.availableRuntimes) { runtime in
                    Button {
                        Task { await model.changeRuntime(to: runtime.id) }
                    } label: {
                        Label {
                            Text(runtime.label ?? runtime.id)
                        } icon: {
                            RuntimeIconView(runtime: runtime.id, size: 16)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                RuntimeIconView(runtime: model.selectedRuntime, size: 14)
                Text(model.selectedRuntime.isEmpty ? "Runtime" : model.selectedRuntime)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .weeFont(.caption2, weight: .bold)
                    .opacity(0.75)
            }
            .weeFont(.caption, weight: .semibold)
            .foregroundStyle(WeeTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(WeeTheme.accent.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(WeeTheme.glassStroke))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.availableRuntimes.isEmpty || model.isLoading)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(groupedModels, id: \.key) { group, models in
                Section(group) {
                    ForEach(models, id: \.id) { entry in
                        Button {
                            Task { await model.changeModel(to: entry.id) }
                        } label: {
                            Label(entry.label, systemImage: entry.id == model.selectedModel ? "checkmark.circle.fill" : "cpu")
                        }
                    }
                }
            }
        } label: {
            HeaderChip(
                symbol: "cpu",
                text: selectedModelLabel,
                background: Color.white.opacity(0.08),
                foreground: WeeTheme.textPrimary,
                showsDisclosure: true
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.availableModels.isEmpty || model.isLoading)
    }

    private var fullAccessButton: some View {
        Button {
            Task { await model.toggleFullAccess() }
        } label: {
            HeaderChip(
                symbol: model.selectedPermissionMode == "elevated" ? "lock.open.fill" : "lock.fill",
                text: "Full Access",
                background: model.selectedPermissionMode == "elevated" ? WeeTheme.accent.opacity(0.18) : Color.white.opacity(0.08),
                foreground: model.selectedPermissionMode == "elevated" ? WeeTheme.accent : WeeTheme.textSecondary,
                showsDisclosure: false
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isLoading)
    }

    private var groupedModels: [(key: String, value: [ModelCatalogEntry])] {
        Dictionary(grouping: model.availableModels) { entry in
            let trimmed = (entry.group ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Models" : trimmed
        }
        .sorted { $0.key < $1.key }
    }

    private var selectedModelLabel: String {
        if let entry = model.availableModels.first(where: { $0.id == model.selectedModel }) {
            return entry.label
        }
        return model.selectedModel.isEmpty ? "Model" : model.selectedModel
    }
}

private struct HeaderChip: View {
    let symbol: String
    let text: String
    let background: Color
    let foreground: Color
    let showsDisclosure: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(text)
                .lineLimit(1)
            if showsDisclosure {
                Image(systemName: "chevron.down")
                    .weeFont(.caption2, weight: .bold)
                    .opacity(0.75)
            }
        }
        .weeFont(.caption, weight: .semibold)
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay(Capsule().stroke(WeeTheme.glassStroke))
    }
}

private struct ContextUsageRing: View {
    let usage: SessionContextUsage

    private var compactionProgress: Double? {
        guard usage.runtime == "wee", let trigger = usage.compactionTriggerTokens else { return nil }
        return min(1, max(0, Double(trigger) / Double(max(usage.contextWindow, 1))))
    }

    private var tooltip: String {
        var text = "Context: \(usage.currentContextTokens.formatted()) / \(usage.contextWindow.formatted()) tokens (\(Int((usage.progress * 100).rounded()))%)"
        if let trigger = usage.compactionTriggerTokens {
            text += " · Wee compacts at \(trigger.formatted()) tokens"
        }
        return text
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(WeeTheme.surfaceHover, lineWidth: 4)
            Circle()
                .trim(from: 0, to: usage.progress)
                .stroke(usage.progress >= 0.75 ? WeeTheme.gold : WeeTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let compactionProgress {
                Capsule()
                    .fill(WeeTheme.gold)
                    .frame(width: 2, height: 6)
                    .offset(y: -13)
                    .rotationEffect(.degrees(compactionProgress * 360))
            }
            Text("\(Int((usage.progress * 100).rounded()))")
                .weeFont(size: 8, weight: .bold)
        }
        .frame(width: 30, height: 30)
        .accessibilityLabel(tooltip)
        .help(tooltip)
    }
}

private enum RecentChatsRailLayout {
    case horizontal
    case vertical
}

private struct RecentChatsRail: View {
    @Bindable var model: WeeAppModel
    var layout: RecentChatsRailLayout = .horizontal
    @State private var sessionToRename: HistorySessionSummary?
    @State private var renameDraft = ""

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                if !model.visibleHistorySessions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(model.visibleHistorySessions.prefix(12)) { session in
                            sessionButton(session, width: 200)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .scrollIndicators(.hidden)
                .glassPanel()
                }

            case .vertical:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("RECENT CHATS")
                            .weeFont(size: 9, weight: .bold)
                            .tracking(1)
                            .foregroundStyle(WeeTheme.textMuted)
                        Spacer()
                        Text("\(model.visibleHistorySessions.count)")
                            .weeFont(.caption2).monospacedDigit()
                            .foregroundStyle(WeeTheme.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    ScrollView {
                        if model.visibleHistorySessions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(WeeTheme.textMuted)
                                Text("Your recent sessions will appear here.")
                                    .weeFont(.caption)
                                    .foregroundStyle(WeeTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(18)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(model.visibleHistorySessions.prefix(24)) { session in
                                    sessionButton(session)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.bottom, 9)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .glassPanel()
            }
        }
        .alert("Rename Chat", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("Chat name", text: $renameDraft)
            Button("Save") {
                if let sessionToRename {
                    model.renameHistorySession(sessionToRename, to: renameDraft)
                }
                sessionToRename = nil
            }
            Button("Cancel", role: .cancel) { sessionToRename = nil }
        } message: {
            Text("Use a name that helps you find this conversation later.")
        }
    }

    private func sessionButton(_ session: HistorySessionSummary, width: CGFloat? = nil) -> some View {
        Button {
            Task { await model.selectHistorySession(session) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(model.title(for: session))
                        .weeFont(.caption, weight: .semibold)
                        .lineLimit(1)
                    if model.isSessionStreaming(session.sessionID) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(WeeTheme.accent)
                            .help("Streaming")
                    }
                    if session.sessionID == model.currentSessionID {
                        Image(systemName: "checkmark.circle.fill")
                            .weeFont(.caption)
                            .foregroundStyle(WeeTheme.accent)
                    }
                }
                HStack(spacing: 5) {
                    Circle()
                        .fill(ChatAgentColor.color(for: session.agent))
                        .frame(width: 7, height: 7)
                    Text(session.agent ?? "agent")
                        .weeFont(.caption2, weight: .medium)
                        .foregroundStyle(ChatAgentColor.color(for: session.agent))
                        .lineLimit(1)
                }
                Text(session.displayPreview)
                    .weeFont(.caption2)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(width == nil ? 2 : 1)
            }
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .padding(8)
            .background(session.sessionID == model.currentSessionID ? WeeTheme.accent.opacity(0.14) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(session.sessionID == model.currentSessionID ? WeeTheme.accent.opacity(0.34) : WeeTheme.glassStroke))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameDraft = model.title(for: session)
                sessionToRename = session
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                model.archiveHistorySession(session)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }
    }
}

private struct SessionHistorySheet: View {
    @Bindable var model: WeeAppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat History")
                    .weeFont(.title3, weight: .bold)
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            List {
                Section {
                    Button {
                        isPresented = false
                        Task { await model.startNewChat() }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }

                Section("Previous Chats") {
                    ForEach(model.visibleHistorySessions) { session in
                        Button {
                            isPresented = false
                            Task { await model.selectHistorySession(session) }
                        } label: {
                            HistorySessionRow(
                                session: session,
                                isSelected: session.sessionID == model.currentSessionID,
                                isStreaming: model.isSessionStreaming(session.sessionID)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !model.archivedHistorySessions.isEmpty {
                    Section("Archived Chats") {
                        ForEach(model.archivedHistorySessions) { session in
                            HStack {
                                Text(model.title(for: session))
                                    .lineLimit(1)
                                Spacer()
                                Button("Restore") {
                                    model.restoreHistorySession(session)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 480, height: 520)
        .background(WeeTheme.background)
        .task {
            await model.loadHistorySessions()
        }
    }
}

private struct HistorySessionRow: View {
    let session: HistorySessionSummary
    let isSelected: Bool
    var isStreaming: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "bubble.left.and.bubble.right")
                .foregroundStyle(isSelected ? WeeTheme.accent : WeeTheme.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .weeFont(.subheadline, weight: .semibold)
                        .foregroundStyle(WeeTheme.textPrimary)
                        .lineLimit(1)
                    if isStreaming {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(WeeTheme.accent)
                            .help("Streaming")
                    }
                }

                Text(session.displayPreview)
                    .weeFont(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(2)

                if let agent = session.agent, !agent.isEmpty {
                    Text(agent)
                        .weeFont(.caption2, weight: .semibold)
                        .foregroundStyle(WeeTheme.gold)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isPreparingSpeech: Bool
    let isSpeaking: Bool
    let userAvatarImage: NSImage?
    let onSpeak: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 30)
            } else if message.role == .assistant {
                AvatarView(isUser: false, customImage: nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.role.rawValue.capitalized)
                        .weeFont(.caption2, weight: .bold)
                        .foregroundStyle(roleColor)
                        .textCase(.uppercase)

                    Spacer(minLength: 8)

                    if message.role == .assistant && !message.text.isEmpty && !isStreaming {
                        Button(action: onSpeak) {
                            Group {
                                if isPreparingSpeech {
                                    ProgressView().controlSize(.mini).tint(WeeTheme.accent)
                                } else {
                                    Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                        .weeFont(.caption)
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isSpeaking ? WeeTheme.gold : WeeTheme.textSecondary)
                        .help(isSpeaking ? "Stop reading" : "Read response aloud")
                        .accessibilityLabel(isSpeaking ? "Stop reading response" : "Read response aloud")
                    }
                }

                ForEach(message.attachments.filter(\.isImage)) { attachment in
                    if let img = attachment.nsImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 320, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }

                ForEach(message.attachments.filter { !$0.isImage }) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: "doc.fill")
                            .weeFont(.caption)
                        Text(attachment.filename)
                            .weeFont(.caption)
                    }
                    .foregroundStyle(WeeTheme.textSecondary)
                    .padding(6)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                if !message.toolActivities.isEmpty {
                    ToolActivityTimeline(activities: message.toolActivities)
                }

                if !message.text.isEmpty {
                    MarkdownText(message.text)
                }

                if isStreaming {
                    StreamingCursor()
                        .padding(.top, message.text.isEmpty ? 0 : 2)
                }
            }
            .padding(11)
            .background(bubbleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WeeTheme.glassStroke))

            if message.role == .user {
                AvatarView(isUser: true, customImage: userAvatarImage)
            }
            if message.role != .user {
                Spacer(minLength: 30)
            }
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user: WeeTheme.accent
        case .assistant: WeeTheme.gold
        case .system: WeeTheme.textMuted
        }
    }

    private var bubbleFill: Color {
        switch message.role {
        case .user: WeeTheme.accent.opacity(0.13)
        case .assistant: Color.white.opacity(0.07)
        case .system: WeeTheme.sunken
        }
    }
}

private struct ToolActivityTimeline: View {
    let activities: [ChatToolActivity]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACTIVITY")
                .weeFont(.caption2, weight: .bold)
                .tracking(0.7)
                .foregroundStyle(WeeTheme.textMuted)

            ForEach(activities) { activity in
                ToolActivityRow(activity: activity)
            }
        }
        .padding(8)
        .background(WeeTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ToolActivityRow: View {
    let activity: ChatToolActivity
    @State private var isExpanded = false

    private var hasDetails: Bool {
        activity.input?.isEmpty == false || activity.output?.isEmpty == false
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let input = activity.input, !input.isEmpty {
                    toolDetail(title: "INPUT", text: input)
                }
                if let output = activity.output, !output.isEmpty {
                    toolDetail(title: activity.isError ? "ERROR" : "RESULT", text: output)
                }
                if !hasDetails {
                    Text("Tool details were not included in this stream event.")
                        .weeFont(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .weeFont(.caption, weight: .semibold)
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
            }
        }
        .tint(WeeTheme.textSecondary)
        .padding(8)
        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func toolDetail(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .weeFont(.caption2, weight: .bold)
                .tracking(0.6)
                .foregroundStyle(WeeTheme.textMuted)
            Text(text)
                .weeFont(.caption2, design: .monospaced)
                .foregroundStyle(WeeTheme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }

    private var statusText: String {
        if activity.isRunning { return "Running \(activity.name)" }
        return activity.isError ? "Failed \(activity.name)" : "Completed \(activity.name)"
    }

    private var statusSymbol: String {
        activity.isRunning ? "circle.dotted" : (activity.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
    }

    private var statusColor: Color {
        activity.isRunning ? WeeTheme.gold : (activity.isError ? WeeTheme.danger : WeeTheme.emerald)
    }
}

/// Issue #25: assistant messages show the Wee icon; user messages show a
/// custom uploaded image if set (Local/Remote Settings → Appearance),
/// falling back to a default person icon otherwise.
private struct AvatarView: View {
    let isUser: Bool
    let customImage: NSImage?

    var body: some View {
        Group {
            if isUser {
                if let customImage {
                    Image(nsImage: customImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(WeeTheme.textSecondary)
                        .background(WeeTheme.sunken)
                }
            } else {
                Image("WeeIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(5)
                    .background(WeeTheme.accent.opacity(0.16))
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().stroke(WeeTheme.glassStroke))
    }
}

private struct ContextBoundaryBanner: View {
    let text: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Rectangle().fill(WeeTheme.danger.opacity(0.35)).frame(height: 1)
                Label("Context reset — the assistant can no longer see messages above this line", systemImage: "exclamationmark.triangle.fill")
                    .weeFont(.caption2, weight: .semibold)
                    .foregroundStyle(WeeTheme.danger)
                    .lineLimit(1)
                    .fixedSize()
                Rectangle().fill(WeeTheme.danger.opacity(0.35)).frame(height: 1)
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .weeFont(.caption2)
                    .foregroundStyle(WeeTheme.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct StreamingCursor: View {
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(WeeTheme.gold)
            .frame(width: 3, height: 18)
            .opacity(isVisible ? 1 : 0.18)
            .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: isVisible)
            .task {
                isVisible = false
            }
            .accessibilityLabel("Streaming response")
    }
}

@MainActor
@Observable
private final class ChatVoiceController: NSObject, AVAudioPlayerDelegate {
    var isRecording = false
    var isTranscribing = false
    var elapsedSeconds = 0
    var loadingMessageID: UUID?
    var speakingMessageID: UUID?
    var statusMessage: String?
    var statusIsError = false

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var recordingModel: WeeAppModel?
    private var transcriptionHandler: ((String) -> Void)?
    private var audioPlayer: AVAudioPlayer?
    private var speechRequestID: UUID?

    var elapsedText: String {
        String(format: "%02d:%02d", elapsedSeconds / 60, elapsedSeconds % 60)
    }

    func toggleRecording(model: WeeAppModel, onTranscription: @escaping (String) -> Void) async {
        if isRecording {
            await stopRecording()
        } else {
            await startRecording(model: model, onTranscription: onTranscription)
        }
    }

    func toggleSpeech(for message: ChatMessage, model: WeeAppModel) async {
        if speakingMessageID == message.id || loadingMessageID == message.id {
            stopPlayback()
            statusMessage = nil
            return
        }

        stopPlayback()
        let readableText = sanitizedSpeechText(message.text)
        guard !readableText.isEmpty else {
            setError("There is no readable text in this response.")
            return
        }

        let requestID = UUID()
        speechRequestID = requestID
        loadingMessageID = message.id
        statusIsError = false
        statusMessage = "Generating speech…"

        do {
            let audioData = try await model.client.textToSpeech(readableText)
            guard speechRequestID == requestID else { return }
            let player = try AVAudioPlayer(data: audioData)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw WeeAPIError.invalidResponse }
            audioPlayer = player
            loadingMessageID = nil
            speakingMessageID = message.id
            statusMessage = "Reading response aloud"
        } catch {
            guard speechRequestID == requestID else { return }
            stopPlayback()
            setError("Speech playback failed: \(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        speechRequestID = nil
        audioPlayer?.stop()
        audioPlayer = nil
        loadingMessageID = nil
        speakingMessageID = nil
    }

    func cancelAll() {
        recorder?.stop()
        cleanupRecording()
        isTranscribing = false
        stopPlayback()
        statusMessage = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.finishPlayback()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.stopPlayback()
            self?.setError("Unable to decode generated speech audio.")
        }
    }

    private func startRecording(model: WeeAppModel, onTranscription: @escaping (String) -> Void) async {
        statusMessage = nil
        statusIsError = false

        guard let sessionID = await model.ensureChatSession() else {
            setError(model.errorMessage ?? "Start a chat session before recording.")
            return
        }
        guard await microphoneAccessGranted() else {
            setError("Microphone access is required. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wee-recording-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.prepareToRecord()
            guard recorder.record() else { throw WeeAPIError.invalidResponse }
            self.recorder = recorder
            recordingURL = url
            recordingModel = model
            transcriptionHandler = onTranscription
            isRecording = true
            elapsedSeconds = 0
            statusMessage = "Recording… click the microphone again to stop"

            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.elapsedSeconds += 1
                    if self.elapsedSeconds >= 300 { await self.stopRecording() }
                }
            }
            recordingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            _ = sessionID
        } catch {
            cleanupRecording()
            setError("Could not start recording: \(error.localizedDescription)")
        }
    }

    private func stopRecording() async {
        guard isRecording, let recorder, let url = recordingURL, let model = recordingModel else { return }
        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isTranscribing = true
        statusMessage = "Transcribing recording…"

        defer {
            isTranscribing = false
            cleanupRecording()
        }

        do {
            guard let sessionID = model.currentSessionID else { throw WeeAPIError.invalidResponse }
            let data = try Data(contentsOf: url)
            guard data.count <= 25 * 1024 * 1024 else {
                setError("Recording exceeds the 25 MB transcription limit.")
                return
            }
            let response = try await model.client.transcribeAudio(
                sessionID: sessionID,
                data: data,
                filename: "recording.m4a",
                mimeType: "audio/mp4"
            )
            let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                setError("No speech was detected in the recording.")
                return
            }
            transcriptionHandler?(text)
            statusIsError = false
            statusMessage = response.backend.map { "Transcribed via \($0)" } ?? "Transcription added to message"
        } catch {
            setError("Transcription failed: \(error.localizedDescription)")
        }
    }

    private func microphoneAccessGranted() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }

    private func cleanupRecording() {
        recorder = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingModel = nil
        transcriptionHandler = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        isRecording = false
        elapsedSeconds = 0
    }

    private func finishPlayback() {
        stopPlayback()
        statusMessage = nil
    }

    private func setError(_ message: String) {
        statusIsError = true
        statusMessage = message
    }

    private func sanitizedSpeechText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "(?s)```.*?```", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "`[^`]+`", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^\\)]+\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[#*_>]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

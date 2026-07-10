import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var model: WeeAppModel
    @State private var draft = ""
    @State private var isShowingHistory = false
    @State private var pendingAttachments: [ChatAttachment] = []
    @State private var isDropTargeted = false
    @State private var isShowingFilePicker = false

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
                                .font(.largeTitle)
                            Text("Drop files here")
                                .font(.headline)
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
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.chatMessages) { message in
                        ChatBubble(message: message, isStreaming: isStreaming(message))
                            .id(message.id)
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
        model.isLoading
            && message.role == .assistant
            && model.chatMessages.last?.id == message.id
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !pendingAttachments.isEmpty {
                attachmentPreview
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    isShowingFilePicker = true
                } label: {
                    Image(systemName: "paperclip")
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .help("Attach file")

                TextField("Message Wee", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit {
                        sendDraft()
                    }

                Button {
                    sendDraft()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty || model.isLoading)
                .keyboardShortcut(.return, modifiers: .command)
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
                                    .font(.title3)
                                Text(attachment.filename)
                                    .font(.caption2)
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
                                .font(.caption)
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
        guard !model.isLoading else { return }

        draft = ""
        pendingAttachments = []
        Task {
            await model.sendChat(prompt, attachments: attachments)
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

private struct HeaderPanel: View {
    @Bindable var model: WeeAppModel
    @Binding var isShowingHistory: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CHAT SESSION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(WeeTheme.textMuted)
                Text(model.currentSessionID ?? "New Session")
                    .font(.system(size: 15, weight: .bold))
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
                    .font(.caption2.weight(.bold))
                    .opacity(0.75)
            }
            .font(.caption.weight(.semibold))
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
                    .font(.caption2.weight(.bold))
                    .opacity(0.75)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
        .overlay(Capsule().stroke(WeeTheme.glassStroke))
    }
}

private enum RecentChatsRailLayout {
    case horizontal
    case vertical
}

private struct RecentChatsRail: View {
    @Bindable var model: WeeAppModel
    var layout: RecentChatsRailLayout = .horizontal

    var body: some View {
        switch layout {
            case .horizontal:
                if !model.historySessions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(model.historySessions.prefix(12)) { session in
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
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(WeeTheme.textMuted)
                        Spacer()
                        Text("\(model.historySessions.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(WeeTheme.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                    ScrollView {
                        if model.historySessions.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left")
                                    .foregroundStyle(WeeTheme.textMuted)
                                Text("Your recent sessions will appear here.")
                                    .font(.caption)
                                    .foregroundStyle(WeeTheme.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(18)
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(model.historySessions.prefix(24)) { session in
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

    private func sessionButton(_ session: HistorySessionSummary, width: CGFloat? = nil) -> some View {
        Button {
            Task { await model.selectHistorySession(session) }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(session.displayTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    if session.sessionID == model.currentSessionID {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(WeeTheme.accent)
                    }
                }
                Text(session.agent ?? "agent")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(WeeTheme.gold)
                    .lineLimit(1)
                Text(session.displayPreview)
                    .font(.caption2)
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
    }
}

private struct SessionHistorySheet: View {
    @Bindable var model: WeeAppModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat History")
                    .font(.title3.weight(.bold))
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
                    ForEach(model.historySessions) { session in
                        Button {
                            isPresented = false
                            Task { await model.selectHistorySession(session) }
                        } label: {
                            HistorySessionRow(session: session, isSelected: session.sessionID == model.currentSessionID)
                        }
                        .buttonStyle(.plain)
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "bubble.left.and.bubble.right")
                .foregroundStyle(isSelected ? WeeTheme.accent : WeeTheme.textSecondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)
                    .lineLimit(1)

                Text(session.displayPreview)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(2)

                if let agent = session.agent, !agent.isEmpty {
                    Text(agent)
                        .font(.caption2.weight(.semibold))
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

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 30)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role.rawValue.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(roleColor)
                    .textCase(.uppercase)

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
                            .font(.caption)
                        Text(attachment.filename)
                            .font(.caption)
                    }
                    .foregroundStyle(WeeTheme.textSecondary)
                    .padding(6)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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

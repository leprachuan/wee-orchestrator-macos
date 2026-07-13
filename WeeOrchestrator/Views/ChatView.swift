import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import Observation

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
        .onDisappear { voice.cancelAll() }
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
            if !pendingAttachments.isEmpty {
                attachmentPreview
            }

            if let voiceStatus = voice.statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: voice.statusIsError ? "exclamationmark.triangle.fill" : "waveform")
                    Text(voiceStatus).lineLimit(1)
                    Spacer()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(voice.statusIsError ? WeeTheme.danger : WeeTheme.accent)
                .padding(.horizontal, 4)
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
                                .font(.caption2.monospacedDigit().weight(.semibold))
                        }
                    }
                    .frame(minWidth: 20, minHeight: 20)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(voice.isTranscribing)
                .help(voice.isRecording ? "Stop and transcribe recording" : "Record voice message")

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
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty || model.isCurrentSessionStreaming)
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
        guard !model.isCurrentSessionStreaming else { return }

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
                environmentMenu
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
    let isPreparingSpeech: Bool
    let isSpeaking: Bool
    let onSpeak: () -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 30)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.role.rawValue.capitalized)
                        .font(.caption2.weight(.bold))
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
                                        .font(.caption)
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

private struct ContextBoundaryBanner: View {
    let text: String

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Rectangle().fill(WeeTheme.danger.opacity(0.35)).frame(height: 1)
                Label("Context reset — the assistant can no longer see messages above this line", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WeeTheme.danger)
                    .lineLimit(1)
                    .fixedSize()
                Rectangle().fill(WeeTheme.danger.opacity(0.35)).frame(height: 1)
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.caption2)
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

import SwiftUI

struct ChatView: View {
    @Bindable var model: WeeAppModel
    @State private var draft = ""
    @State private var isShowingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            HeaderPanel(model: model, isShowingHistory: $isShowingHistory)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            RecentChatsRail(model: model)
                .frame(height: 82)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            chatTranscript
                .padding(.horizontal, 16)
                .padding(.top, 8)

            inputBar
                .padding(16)
        }
        .sheet(isPresented: $isShowingHistory) {
            SessionHistorySheet(model: model, isPresented: $isShowingHistory)
        }
    }

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.chatMessages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(14)
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

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
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
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(10)
        .glassPanel()
    }

    private func sendDraft() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !model.isLoading else { return }

        draft = ""
        Task {
            await model.sendChat(prompt)
        }
    }
}

private struct HeaderPanel: View {
    @Bindable var model: WeeAppModel
    @Binding var isShowingHistory: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.currentSessionID ?? "New Session")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(WeeTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    agentMenu
                    runtimeMenu
                    modelMenu
                    fullAccessButton
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 10) {
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
        .padding(14)
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
            ForEach(model.availableRuntimes) { runtime in
                Button {
                    Task { await model.changeRuntime(to: runtime.id) }
                } label: {
                    Text(runtime.id == model.selectedRuntime ? "✓ \(runtime.displayLabel)" : runtime.displayLabel)
                }
            }
        } label: {
            HeaderChip(
                symbol: "server.rack",
                text: model.selectedRuntime.isEmpty ? "Runtime" : selectedRuntimeLabel,
                background: WeeTheme.accent.opacity(0.18),
                foreground: WeeTheme.accent,
                showsDisclosure: true
            )
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

    private var selectedRuntimeLabel: String {
        if let entry = model.availableRuntimes.first(where: { $0.id == model.selectedRuntime }) {
            return entry.displayLabel
        }
        return model.selectedRuntime
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

private struct RecentChatsRail: View {
    @Bindable var model: WeeAppModel

    var body: some View {
        if model.historySessions.isEmpty { EmptyView() }
        else {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.historySessions.prefix(12)) { session in
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
                                    .lineLimit(1)
                            }
                            .frame(width: 200, alignment: .leading)
                            .padding(10)
                            .background(session.sessionID == model.currentSessionID ? WeeTheme.accent.opacity(0.14) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(session.sessionID == model.currentSessionID ? WeeTheme.accent.opacity(0.34) : WeeTheme.glassStroke))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .glassPanel()
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

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role.rawValue.capitalized)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(roleColor)
                    .textCase(.uppercase)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(WeeTheme.textPrimary)
                    .textSelection(.enabled)
            }
            .padding(13)
            .background(bubbleFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WeeTheme.glassStroke))

            if message.role != .user {
                Spacer(minLength: 60)
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

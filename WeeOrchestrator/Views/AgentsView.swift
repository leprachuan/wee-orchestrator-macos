import SwiftUI

struct AgentsView: View {
    @Bindable var model: WeeAppModel
    @State private var editorContext: AgentEditorContext?

    var body: some View {
        VStack(spacing: 8) {
            PageHeader(title: "Agents", subtitle: "\(model.localAgents.count) local · \(model.remoteAgents.count) remote", symbol: "person.2.fill") {
                Picker("Environment", selection: environmentBinding) {
                    ForEach(WeeEnvironment.allCases) { environment in
                        Label(environment.title, systemImage: environment.symbol).tag(environment)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 190)

                Picker("Active", selection: $model.selectedAgent) {
                    ForEach(model.agents) { agent in
                        Text(agent.name).tag(agent.name)
                    }
                }
                .frame(width: 200)

                Button {
                    editorContext = AgentEditorContext(agentName: nil)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .help("Add Agent")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    agentSection(.local)
                    agentSection(.remote)
                }
                .padding(10)
            }
            .scrollIndicators(.hidden)
            .glassPanel(fill: WeeTheme.background)
        }
        .padding(10)
        .sheet(item: $editorContext) { context in
            AgentEditorSheet(model: model, agentName: context.agentName)
                .frame(width: 760, height: 720)
        }
    }

    private var environmentBinding: Binding<WeeEnvironment> {
        Binding(
            get: { model.activeEnvironment },
            set: { environment in Task { await model.switchEnvironment(to: environment) } }
        )
    }

    @ViewBuilder
    private func agentSection(_ environment: WeeEnvironment) -> some View {
        let sourceAgents = model.agents(for: environment)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("\(environment.title) Agents", systemImage: environment.symbol)
                    .weeFont(.headline, weight: .semibold)
                    .foregroundStyle(model.activeEnvironment == environment ? WeeTheme.accent : WeeTheme.textPrimary)
                StatusPill(text: "\(sourceAgents.count)", color: model.activeEnvironment == environment ? WeeTheme.accent : WeeTheme.textSecondary)
                if model.activeEnvironment == environment {
                    StatusPill(text: "active environment", color: WeeTheme.emerald, symbol: "checkmark.circle.fill")
                }
                Spacer()
                Button {
                    Task {
                        await model.switchEnvironment(to: environment)
                        editorContext = AgentEditorContext(agentName: nil)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            if sourceAgents.isEmpty {
                Text(environment == .local ? "Start or connect to the local API to load local agents." : "Configure the remote API in Settings to load remote agents.")
                    .weeFont(.subheadline)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WeeTheme.surface, in: RoundedRectangle(cornerRadius: 9))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 8, alignment: .top)], alignment: .leading, spacing: 8) {
                    ForEach(sourceAgents) { agent in
                        AgentCard(
                            agent: agent,
                            isSelected: model.activeEnvironment == environment && agent.name == model.selectedAgent,
                            onEdit: {
                                Task {
                                    await model.switchEnvironment(to: environment)
                                    editorContext = AgentEditorContext(agentName: agent.name)
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task {
                                await model.switchEnvironment(to: environment)
                                model.selectedAgent = agent.name
                                model.saveConfiguration()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct AgentEditorContext: Identifiable {
    let id = UUID()
    let agentName: String?
}

private struct AgentCard: View {
    let agent: AgentSummary
    let isSelected: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(isSelected ? WeeTheme.accent.opacity(0.16) : WeeTheme.surfaceHover)
                        Text(String(agent.name.prefix(1)).uppercased())
                            .weeFont(.caption, weight: .bold)
                            .foregroundStyle(isSelected ? WeeTheme.accent : WeeTheme.textSecondary)
                    }
                    .frame(width: 27, height: 27)
                    Text(agent.name)
                        .weeFont(.headline, weight: .semibold)
                        .foregroundStyle(isSelected ? WeeTheme.accent : WeeTheme.textPrimary)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .help("Edit \(agent.name)")

                if isSelected { StatusPill(text: "active", color: WeeTheme.emerald, symbol: "checkmark") }
            }

            Text(agent.description)
                .weeFont(.subheadline)
                .foregroundStyle(WeeTheme.textSecondary)
                .lineLimit(2)

            HStack {
                if let runtime = agent.primaryRuntime {
                    StatusPill(text: runtime, color: WeeTheme.accent, symbol: "terminal")
                }
                if let model = agent.primaryModel {
                    StatusPill(text: model, color: WeeTheme.gold, symbol: "cpu")
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .background(isSelected ? WeeTheme.accent.opacity(0.09) : WeeTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isSelected ? WeeTheme.accent.opacity(0.5) : WeeTheme.glassStroke))
    }
}

private struct AgentEditorSheet: View {
    @Bindable var model: WeeAppModel
    let agentName: String?
    @Environment(\.dismiss) private var dismiss

    @State private var agentsConfig = AgentsConfigResponse(agents: [])
    @State private var selectedAgentName = ""
    @State private var draftAgent = AgentConfiguration()
    @State private var originalAgent = AgentConfiguration()
    @State private var status: String?
    @State private var statusIsError = false
    @State private var showDeleteConfirmation = false
    @State private var isLoaded = false
    @State private var instructions = ""
    @State private var loadedInstructions = ""
    @State private var instructionsExists = false
    @State private var isLoadingInstructions = false
    @State private var isSavingInstructions = false
    @State private var instructionsStatus: String?
    @State private var instructionsStatusIsError = false
    @State private var webexBotState = BotChannelUIState()
    @State private var telegramBotState = BotChannelUIState()
    @State private var memoryEntries: [AgentMemoryEntry] = []
    @State private var selectedMemoryName: String?
    @State private var selectedMemoryContent = ""
    @State private var loadedMemoryContent = ""
    @State private var selectedMemoryExists = false
    @State private var isLoadingMemoryList = false
    @State private var isLoadingMemoryContent = false
    @State private var isSavingMemory = false
    @State private var memoriesStatus: String?
    @State private var memoriesStatusIsError = false

    private let runtimeFallbacks = ["wee", "copilot", "copilot-sdk", "claude", "claude-sdk", "gemini", "opencode", "codex", "devin"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(agentName == nil ? "New Agent" : "Edit Agent")
                    .weeFont(.title3, weight: .bold)
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    agentDetailsSection
                    permissionsSection
                    instructionsSection
                    memoriesSection
                    botSection(title: "Webex Bot", systemImage: "message.badge", channel: "webex", state: $webexBotState)
                    botSection(title: "Telegram Bot", systemImage: "paperplane", channel: "telegram", state: $telegramBotState)
                    actionSection
                }
                .padding([.horizontal, .bottom], 16)
            }
            .scrollIndicators(.hidden)
        }
        .background(WeeTheme.background)
        .task {
            await loadIfNeeded()
        }
        // Reload per selected agent so one agent's instructions are never left
        // on screen — or saved — while another is selected.
        .task(id: selectedAgentName) {
            await loadInstructions(for: selectedAgentName)
            await loadBotStatus(for: selectedAgentName, channel: "webex", state: $webexBotState)
            await loadBotStatus(for: selectedAgentName, channel: "telegram", state: $telegramBotState)
            await loadMemoryList(for: selectedAgentName)
        }
        .confirmationDialog("Delete Agent?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete \(selectedAgentName)", role: .destructive) {
                Task { await deleteSelectedAgent() }
            }
        } message: {
            Text("This removes the agent from the shared agents config.")
        }
    }

    /// The selected agent's AGENTS.md.
    ///
    /// Loaded per agent and reloaded when the selection changes, so one agent's
    /// instructions are never shown or saved while another is selected.
    private var instructionsSection: some View {
        AgentEditorSection(title: "Instructions (AGENTS.md)", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                if isLoadingInstructions {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading instructions…")
                            .weeFont(.caption)
                            .foregroundStyle(WeeTheme.textSecondary)
                    }
                } else {
                    if instructionsExists == false {
                        Text("This agent has no AGENTS.md yet. Saving creates one.")
                            .weeFont(.caption)
                            .foregroundStyle(WeeTheme.textMuted)
                    }

                    TextEditor(text: $instructions)
                        .weeFont(.caption, design: .monospaced)
                        .foregroundStyle(WeeTheme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 220)
                        .padding(8)
                        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
                        .disabled(selectedAgentName.isEmpty)

                    HStack(spacing: 10) {
                        Button {
                            Task { await saveInstructions() }
                        } label: {
                            HStack(spacing: 6) {
                                if isSavingInstructions { ProgressView().controlSize(.small) }
                                Text("Save Instructions")
                            }
                        }
                        .buttonStyle(WeePrimaryButtonStyle())
                        .disabled(
                            selectedAgentName.isEmpty
                            || isSavingInstructions
                            || instructions == loadedInstructions
                        )

                        Button("Revert") {
                            instructions = loadedInstructions
                            instructionsStatus = nil
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                        .disabled(instructions == loadedInstructions)

                        if let instructionsStatus {
                            Text(instructionsStatus)
                                .weeFont(.caption)
                                .foregroundStyle(instructionsStatusIsError ? WeeTheme.danger : WeeTheme.accent)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    private func loadInstructions(for agent: String) async {
        guard agent.isEmpty == false else { return }
        isLoadingInstructions = true
        instructionsStatus = nil
        defer { isLoadingInstructions = false }
        do {
            let response = try await model.client.agentInstructions(agent: agent)
            instructions = response.content
            loadedInstructions = response.content
            instructionsExists = response.exists
        } catch {
            instructions = ""
            loadedInstructions = ""
            instructionsExists = false
            instructionsStatus = "Could not load instructions: \(error.localizedDescription)"
            instructionsStatusIsError = true
        }
    }

    private func saveInstructions() async {
        let agent = selectedAgentName
        guard agent.isEmpty == false else { return }
        isSavingInstructions = true
        defer { isSavingInstructions = false }
        do {
            try await model.client.saveAgentInstructions(agent: agent, content: instructions)
            // Only trust the save for the agent still selected: the sheet's
            // picker can change while the request is in flight.
            guard agent == selectedAgentName else { return }
            loadedInstructions = instructions
            instructionsExists = true
            instructionsStatus = "Saved"
            instructionsStatusIsError = false
        } catch {
            instructionsStatus = "Save failed: \(error.localizedDescription)"
            instructionsStatusIsError = true
        }
    }

    /// Editable viewer for an agent's memories (issues #65, #461): the durable
    /// MEMORY.md plus dated notes under daily/. Mirrors instructionsSection's
    /// per-agent reload discipline -- switching agents clears the selected
    /// memory and reloads the list, so a stale agent's content is never shown
    /// or saved while another is selected.
    private var memoriesSection: some View {
        AgentEditorSection(title: "Memories", systemImage: "brain") {
            VStack(alignment: .leading, spacing: 8) {
                if isLoadingMemoryList {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading memories…")
                            .weeFont(.caption)
                            .foregroundStyle(WeeTheme.textSecondary)
                    }
                } else if memoryEntries.isEmpty {
                    Text("This agent has no memories yet.")
                        .weeFont(.caption)
                        .foregroundStyle(WeeTheme.textMuted)
                } else {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(memoryEntries) { entry in
                                memoryRow(entry)
                            }
                        }
                        .frame(width: 200, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            if isLoadingMemoryContent {
                                ProgressView().controlSize(.small)
                            } else if let selectedMemoryName {
                                if selectedMemoryExists == false {
                                    Text("\(selectedMemoryName) is empty.")
                                        .weeFont(.caption)
                                        .foregroundStyle(WeeTheme.textMuted)
                                }

                                TextEditor(text: $selectedMemoryContent)
                                    .weeFont(.caption, design: .monospaced)
                                    .foregroundStyle(WeeTheme.textPrimary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 160, maxHeight: 260)
                                    .padding(8)
                                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))

                                HStack(spacing: 10) {
                                    Button {
                                        Task { await saveMemory() }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if isSavingMemory { ProgressView().controlSize(.small) }
                                            Text("Save Memory")
                                        }
                                    }
                                    .buttonStyle(WeePrimaryButtonStyle())
                                    .disabled(
                                        isSavingMemory
                                        || selectedMemoryContent == loadedMemoryContent
                                    )

                                    Button("Revert") {
                                        selectedMemoryContent = loadedMemoryContent
                                        memoriesStatus = nil
                                    }
                                    .buttonStyle(WeeGhostButtonStyle())
                                    .disabled(selectedMemoryContent == loadedMemoryContent)

                                    Spacer()
                                }
                            } else {
                                Text("Select a memory to view and edit its contents.")
                                    .weeFont(.caption)
                                    .foregroundStyle(WeeTheme.textMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let memoriesStatus {
                    Text(memoriesStatus)
                        .weeFont(.caption)
                        .foregroundStyle(memoriesStatusIsError ? WeeTheme.danger : WeeTheme.accent)
                }
            }
        }
    }

    private func memoryRow(_ entry: AgentMemoryEntry) -> some View {
        Button {
            Task { await loadMemoryContent(agent: selectedAgentName, name: entry.name) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: entry.isDaily ? "calendar" : "doc.text.fill")
                        .weeFont(.caption2)
                    Text(entry.isDaily ? String(entry.name.dropFirst("daily/".count)) : entry.name)
                        .weeFont(.caption, weight: .semibold)
                        .lineLimit(1)
                }
                .foregroundStyle(selectedMemoryName == entry.name ? WeeTheme.accent : WeeTheme.textPrimary)
                if entry.summary.isEmpty == false {
                    Text(entry.summary)
                        .weeFont(.caption2)
                        .foregroundStyle(WeeTheme.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(
                selectedMemoryName == entry.name ? WeeTheme.accent.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.isDaily ? "Daily note \(entry.name)" : "Durable memory \(entry.name)")
    }

    private func loadMemoryList(for agent: String) async {
        guard agent.isEmpty == false else { return }
        isLoadingMemoryList = true
        memoriesStatus = nil
        selectedMemoryName = nil
        selectedMemoryContent = ""
        loadedMemoryContent = ""
        defer { isLoadingMemoryList = false }
        do {
            memoryEntries = try await model.client.agentMemories(agent: agent)
        } catch {
            memoryEntries = []
            memoriesStatus = "Could not load memories: \(error.localizedDescription)"
            memoriesStatusIsError = true
        }
    }

    private func loadMemoryContent(agent: String, name: String) async {
        isLoadingMemoryContent = true
        selectedMemoryName = name
        memoriesStatus = nil
        defer { isLoadingMemoryContent = false }
        do {
            let response = try await model.client.agentMemoryContent(agent: agent, name: name)
            // Only trust the result for the agent/memory still selected: both
            // can change while the request is in flight.
            guard agent == selectedAgentName, selectedMemoryName == name else { return }
            selectedMemoryContent = response.content
            loadedMemoryContent = response.content
            selectedMemoryExists = response.exists
        } catch {
            guard agent == selectedAgentName, selectedMemoryName == name else { return }
            selectedMemoryContent = ""
            loadedMemoryContent = ""
            selectedMemoryExists = false
            memoriesStatus = "Could not load \(name): \(error.localizedDescription)"
            memoriesStatusIsError = true
        }
    }

    private func saveMemory() async {
        let agent = selectedAgentName
        guard let name = selectedMemoryName, agent.isEmpty == false else { return }
        isSavingMemory = true
        defer { isSavingMemory = false }
        do {
            try await model.client.saveAgentMemory(agent: agent, name: name, content: selectedMemoryContent)
            // Only trust the save for the agent/memory still selected: both
            // can change while the request is in flight.
            guard agent == selectedAgentName, selectedMemoryName == name else { return }
            loadedMemoryContent = selectedMemoryContent
            selectedMemoryExists = true
            memoriesStatus = "Saved"
            memoriesStatusIsError = false
        } catch {
            memoriesStatus = "Save failed: \(error.localizedDescription)"
            memoriesStatusIsError = true
        }
    }

    /// Per-agent, per-channel bot token + service control + log viewing
    /// (issues #491, #492). Mirrors instructionsSection's per-agent reload
    /// discipline: token/service state is never shown or acted on for a
    /// stale selection. One instance of this per channel (webex, telegram)
    /// keeps the two near-identical sections from being duplicated by hand.
    private func botSection(title: String, systemImage: String, channel: String, state: Binding<BotChannelUIState>) -> some View {
        AgentEditorSection(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                if state.wrappedValue.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading \(title) status…")
                            .weeFont(.caption)
                            .foregroundStyle(WeeTheme.textSecondary)
                    }
                } else {
                    HStack(spacing: 8) {
                        StatusPill(
                            text: state.wrappedValue.tokenStatus.configured ? "token configured" : "no token",
                            color: state.wrappedValue.tokenStatus.configured ? WeeTheme.emerald : WeeTheme.textSecondary,
                            symbol: state.wrappedValue.tokenStatus.configured ? "checkmark.circle.fill" : "circle"
                        )
                        if let serviceStatus = state.wrappedValue.serviceStatus, serviceStatus.supported {
                            StatusPill(
                                text: serviceStatus.running == true ? "running" : "stopped",
                                color: serviceStatus.running == true ? WeeTheme.emerald : WeeTheme.gold,
                                symbol: serviceStatus.running == true ? "bolt.fill" : "bolt.slash"
                            )
                        }
                    }

                    AgentEditorFieldRow(title: "Bot Token") {
                        SecureField(
                            state.wrappedValue.tokenStatus.configured ? "•••••••• (saving replaces the existing token)" : "Paste the \(title.replacingOccurrences(of: " Bot", with: "")) bot token",
                            text: state.tokenInput
                        )
                    }

                    HStack(spacing: 10) {
                        Button {
                            Task { await saveBotToken(channel: channel, state: state) }
                        } label: {
                            HStack(spacing: 6) {
                                if state.wrappedValue.isSavingToken { ProgressView().controlSize(.small) }
                                Text("Save Token")
                            }
                        }
                        .buttonStyle(WeePrimaryButtonStyle())
                        .disabled(selectedAgentName.isEmpty || state.wrappedValue.isSavingToken || state.wrappedValue.tokenInput.isEmpty)

                        Button("Clear Token") {
                            Task { await clearBotToken(channel: channel, state: state) }
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                        .disabled(selectedAgentName.isEmpty || !state.wrappedValue.tokenStatus.configured)

                        Button {
                            Task { await restartBotService(channel: channel, state: state) }
                        } label: {
                            HStack(spacing: 6) {
                                if state.wrappedValue.isRestarting { ProgressView().controlSize(.small) }
                                Text(state.wrappedValue.serviceStatus?.running == true ? "Restart Service" : "Start Service")
                            }
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                        .disabled(
                            selectedAgentName.isEmpty
                            || state.wrappedValue.isRestarting
                            || (selectedAgentName != "orchestrator" && !state.wrappedValue.tokenStatus.configured)
                        )
                        .help(
                            selectedAgentName != "orchestrator" && !state.wrappedValue.tokenStatus.configured
                            ? "Save a bot token before starting this agent's \(title)."
                            : ""
                        )

                        Button("View Logs") {
                            state.wrappedValue.showLogs = true
                            Task { await loadBotLogs(channel: channel, state: state) }
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                        .disabled(selectedAgentName.isEmpty)

                        if let status = state.wrappedValue.status {
                            Text(status)
                                .weeFont(.caption)
                                .foregroundStyle(state.wrappedValue.statusIsError ? WeeTheme.danger : WeeTheme.accent)
                        }

                        Spacer()
                    }
                }
            }
        }
        .sheet(isPresented: state.showLogs) {
            BotLogsSheet(title: title, channel: channel, state: state) {
                await loadBotLogs(channel: channel, state: state)
            }
        }
    }

    private func loadBotStatus(for agent: String, channel: String, state: Binding<BotChannelUIState>) async {
        guard agent.isEmpty == false else { return }
        state.wrappedValue.isLoading = true
        state.wrappedValue.status = nil
        state.wrappedValue.tokenInput = ""
        defer { state.wrappedValue.isLoading = false }
        do {
            state.wrappedValue.tokenStatus = try await model.client.botTokenStatus(agent: agent, channel: channel)
        } catch {
            state.wrappedValue.tokenStatus = BotTokenStatus(agent: agent, channel: channel, configured: false, secretName: nil, allowedUsers: [])
        }
        do {
            state.wrappedValue.serviceStatus = try await model.client.botServiceStatus(agent: agent, channel: channel)
        } catch {
            state.wrappedValue.serviceStatus = nil
        }
    }

    private func saveBotToken(channel: String, state: Binding<BotChannelUIState>) async {
        let agent = selectedAgentName
        guard agent.isEmpty == false, state.wrappedValue.tokenInput.isEmpty == false else { return }
        state.wrappedValue.isSavingToken = true
        defer { state.wrappedValue.isSavingToken = false }
        do {
            try await model.client.saveBotToken(agent: agent, channel: channel, token: state.wrappedValue.tokenInput, allowedUsers: state.wrappedValue.tokenStatus.allowedUsers)
            guard agent == selectedAgentName else { return }
            state.wrappedValue.tokenInput = ""
            state.wrappedValue.tokenStatus = try await model.client.botTokenStatus(agent: agent, channel: channel)
            state.wrappedValue.status = "Token saved"
            state.wrappedValue.statusIsError = false
        } catch {
            state.wrappedValue.status = "Save failed: \(error.localizedDescription)"
            state.wrappedValue.statusIsError = true
        }
    }

    private func clearBotToken(channel: String, state: Binding<BotChannelUIState>) async {
        let agent = selectedAgentName
        guard agent.isEmpty == false else { return }
        state.wrappedValue.isSavingToken = true
        defer { state.wrappedValue.isSavingToken = false }
        do {
            try await model.client.deleteBotToken(agent: agent, channel: channel)
            guard agent == selectedAgentName else { return }
            state.wrappedValue.tokenStatus = BotTokenStatus(agent: agent, channel: channel, configured: false, secretName: nil, allowedUsers: [])
            state.wrappedValue.status = "Token removed"
            state.wrappedValue.statusIsError = false
        } catch {
            state.wrappedValue.status = "Remove failed: \(error.localizedDescription)"
            state.wrappedValue.statusIsError = true
        }
    }

    private func restartBotService(channel: String, state: Binding<BotChannelUIState>) async {
        let agent = selectedAgentName
        guard agent.isEmpty == false else { return }
        state.wrappedValue.isRestarting = true
        defer { state.wrappedValue.isRestarting = false }
        do {
            try await model.client.restartBotService(agent: agent, channel: channel)
            guard agent == selectedAgentName else { return }
            state.wrappedValue.serviceStatus = try await model.client.botServiceStatus(agent: agent, channel: channel)
            state.wrappedValue.status = "Service restarted"
            state.wrappedValue.statusIsError = false
        } catch {
            state.wrappedValue.status = "Restart failed: \(error.localizedDescription)"
            state.wrappedValue.statusIsError = true
        }
    }

    private func loadBotLogs(channel: String, state: Binding<BotChannelUIState>) async {
        let agent = selectedAgentName
        guard agent.isEmpty == false else { return }
        state.wrappedValue.isLoadingLogs = true
        state.wrappedValue.logsError = nil
        defer { state.wrappedValue.isLoadingLogs = false }
        do {
            let response = try await model.client.botLogs(agent: agent, channel: channel)
            guard agent == selectedAgentName else { return }
            state.wrappedValue.logLines = response.lines
        } catch {
            guard agent == selectedAgentName else { return }
            state.wrappedValue.logLines = []
            state.wrappedValue.logsError = "Could not load logs: \(error.localizedDescription)"
        }
    }

    private var agentDetailsSection: some View {
        AgentEditorSection(title: "Agent", systemImage: "person.crop.circle") {
            AgentEditorFieldRow(title: "Name") {
                TextField("agent-name", text: $draftAgent.name)
            }

            AgentEditorFieldRow(title: "Working Path") {
                TextField("/opt/my-agent", text: $draftAgent.path)
            }

            AgentEditorTextAreaRow(title: "Description", text: optionalTextBinding(\.description), minHeight: 74)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                AgentEditorFieldRow(title: "Primary Runtime") {
                    Picker("Primary Runtime", selection: optionalTextBinding(\.primaryRuntime)) {
                        Text("Default").tag("")
                        ForEach(runtimeOptions, id: \.self) { runtime in
                            Text(runtime).tag(runtime)
                        }
                    }
                }

                AgentEditorFieldRow(title: "Primary Model") {
                    TextField("e.g. claude-sonnet-4.6", text: optionalTextBinding(\.primaryModel))
                }

                AgentEditorFieldRow(title: "Fallback Runtime") {
                    Picker("Fallback Runtime", selection: optionalTextBinding(\.fallbackRuntime)) {
                        Text("None").tag("")
                        ForEach(runtimeOptions, id: \.self) { runtime in
                            Text(runtime).tag(runtime)
                        }
                    }
                }

                AgentEditorFieldRow(title: "Fallback Model") {
                    TextField("e.g. gpt-4-turbo", text: optionalTextBinding(\.fallbackModel))
                }

                AgentEditorFieldRow(title: "Max Concurrent Tasks") {
                    TextField("1", text: maxConcurrentBinding)
                }
            }
        }
    }

    private var permissionsSection: some View {
        AgentEditorSection(title: "Permissions", systemImage: "lock.shield.fill") {
            AgentEditorFieldRow(title: "Mode") {
                Picker("Mode", selection: $draftAgent.permissions.mode) {
                    Text("elevated - full access").tag("elevated")
                    Text("restricted - curated tools").tag("restricted")
                    Text("sandboxed - no external access").tag("sandboxed")
                }
            }

            DisclosureGroup("Directories") {
                VStack(spacing: 10) {
                    AgentEditorTextAreaRow(title: "Allow Read", text: allowReadBinding, minHeight: 70)
                    AgentEditorTextAreaRow(title: "Allow Write", text: allowWriteBinding, minHeight: 70)
                    AgentEditorTextAreaRow(title: "Deny", text: directoryDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }

            DisclosureGroup("Tools") {
                VStack(spacing: 10) {
                    AgentEditorTextAreaRow(title: "Allow", text: toolsAllowBinding, minHeight: 70)
                    AgentEditorTextAreaRow(title: "Deny", text: toolsDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }

            DisclosureGroup("Network") {
                VStack(spacing: 10) {
                    AgentEditorTextAreaRow(title: "Allow URLs", text: networkAllowBinding, minHeight: 70)
                    AgentEditorTextAreaRow(title: "Deny URLs", text: networkDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }

            DisclosureGroup("MCP Servers") {
                VStack(spacing: 10) {
                    AgentEditorTextAreaRow(title: "Allow", text: mcpAllowBinding, minHeight: 70)
                    AgentEditorTextAreaRow(title: "Deny", text: mcpDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }
        }
    }

    private var actionSection: some View {
        AgentEditorSection(title: "Actions", systemImage: "slider.horizontal.3") {
            HStack {
                Button {
                    Task { await saveAgentSettings() }
                } label: {
                    Label("Save Agent", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WeePrimaryButtonStyle())

                Button {
                    discardAgentChanges()
                } label: {
                    Label("Discard", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(WeeGhostButtonStyle())

                Button {
                    Task { await reloadAgents() }
                } label: {
                    Label("Reload Agents", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Agent", systemImage: "trash")
            }
            .buttonStyle(WeeGhostButtonStyle())
            .disabled(selectedAgentName.isEmpty || originalAgent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if draftAgent != originalAgent {
                Text("Unsaved agent changes")
                    .weeFont(.caption, weight: .semibold)
                    .foregroundStyle(WeeTheme.gold)
            }

            if let status {
                Text(status)
                    .weeFont(.caption)
                    .foregroundStyle(statusIsError ? WeeTheme.danger : WeeTheme.accent)
            }
        }
    }

    private var maxConcurrentBinding: Binding<String> {
        Binding(
            get: { draftAgent.maxConcurrent.map(String.init) ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draftAgent.maxConcurrent = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
    }

    private var runtimeOptions: [String] {
        Array(
            Set(
                runtimeFallbacks
                    + model.availableRuntimes.map(\.id)
                    + model.agents.compactMap(\.primaryRuntime)
                    + agentsConfig.agents.compactMap(\.primaryRuntime)
                    + agentsConfig.agents.compactMap(\.fallbackRuntime)
            )
        )
        .sorted()
    }

    private var allowReadBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.directories.allowRead }, set: { draftAgent.permissions.directories.allowRead = $0 })
    }

    private var allowWriteBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.directories.allowWrite }, set: { draftAgent.permissions.directories.allowWrite = $0 })
    }

    private var directoryDenyBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.directories.deny }, set: { draftAgent.permissions.directories.deny = $0 })
    }

    private var toolsAllowBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.tools.allow }, set: { draftAgent.permissions.tools.allow = $0 })
    }

    private var toolsDenyBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.tools.deny }, set: { draftAgent.permissions.tools.deny = $0 })
    }

    private var networkAllowBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.network.allowURLs }, set: { draftAgent.permissions.network.allowURLs = $0 })
    }

    private var networkDenyBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.network.denyURLs }, set: { draftAgent.permissions.network.denyURLs = $0 })
    }

    private var mcpAllowBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.mcp.allow }, set: { draftAgent.permissions.mcp.allow = $0 })
    }

    private var mcpDenyBinding: Binding<String> {
        arrayBinding(get: { draftAgent.permissions.mcp.deny }, set: { draftAgent.permissions.mcp.deny = $0 })
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        isLoaded = true
        await loadAgentSettings()
    }

    private func loadAgentSettings() async {
        do {
            let config = try await model.client.agentsConfig()
            agentsConfig = config
            if let agentName, config.agents.contains(where: { $0.name == agentName }) {
                selectAgent(named: agentName)
            } else {
                prepareNewAgent(in: config)
            }
            status = nil
        } catch {
            status = "Failed to load agents: \(error.localizedDescription)"
            statusIsError = true
            prepareNewAgent(in: agentsConfig)
        }
    }

    private func selectAgent(named name: String) {
        guard let agent = agentsConfig.agents.first(where: { $0.name == name }) else { return }
        selectedAgentName = agent.name
        draftAgent = agent
        originalAgent = agent
    }

    private func prepareNewAgent(in config: AgentsConfigResponse) {
        let base = "new-agent"
        var candidate = base
        var index = 2
        while config.agents.contains(where: { $0.name == candidate }) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        selectedAgentName = candidate
        draftAgent = AgentConfiguration(name: candidate, path: "/opt/")
        originalAgent = AgentConfiguration()
    }

    private func saveAgentSettings() async {
        let errors = validate(draftAgent)
        guard errors.isEmpty else {
            status = errors.joined(separator: " ")
            statusIsError = true
            return
        }

        var config = agentsConfig
        if let index = config.agents.firstIndex(where: { $0.name == selectedAgentName }) {
            config.agents[index] = draftAgent
        } else {
            config.agents.append(draftAgent)
        }

        do {
            try await model.client.saveAgentsConfig(config)
            agentsConfig = config
            selectedAgentName = draftAgent.name
            originalAgent = draftAgent
            status = "Agent settings saved."
            statusIsError = false
            await model.refreshAll()
        } catch {
            status = "Save failed: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func discardAgentChanges() {
        draftAgent = originalAgent.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AgentConfiguration(name: selectedAgentName, path: "/opt/") : originalAgent
        status = "Discarded local edits."
        statusIsError = false
    }

    private func reloadAgents() async {
        do {
            try await model.client.reloadAgents()
            status = "Agents reloaded in memory."
            statusIsError = false
            await model.refreshAll()
        } catch {
            status = "Reload failed: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func deleteSelectedAgent() async {
        guard !selectedAgentName.isEmpty else { return }
        var config = agentsConfig
        config.agents.removeAll { $0.name == selectedAgentName }

        do {
            try await model.client.saveAgentsConfig(config)
            agentsConfig = config
            status = "Agent deleted."
            statusIsError = false
            await model.refreshAll()
            dismiss()
        } catch {
            status = "Delete failed: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func optionalTextBinding(_ keyPath: WritableKeyPath<AgentConfiguration, String?>) -> Binding<String> {
        Binding(
            get: { draftAgent[keyPath: keyPath] ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                draftAgent[keyPath: keyPath] = trimmed.isEmpty ? nil : value
            }
        )
    }

    private func arrayBinding(get: @escaping () -> [String], set: @escaping ([String]) -> Void) -> Binding<String> {
        Binding(
            get: { get().joined(separator: "\n") },
            set: { set(Self.parseLines($0)) }
        )
    }

    private func validate(_ agent: AgentConfiguration) -> [String] {
        var errors: [String] = []
        let name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            errors.append("Name is required.")
        } else if name.range(of: #"^[a-z0-9_-]+$"#, options: .regularExpression) == nil {
            errors.append("Name must be lowercase with hyphens or underscores only.")
        } else if agentsConfig.agents.contains(where: { $0.name == name && $0.name != selectedAgentName }) {
            errors.append("Another agent already uses that name.")
        }

        let path = agent.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.isEmpty {
            errors.append("Working path is required.")
        } else if !path.hasPrefix("/") && !path.hasPrefix("~") {
            errors.append("Working path must start with / or ~.")
        }
        if let maxConcurrent = agent.maxConcurrent, maxConcurrent < 1 {
            errors.append("Max concurrent must be at least 1.")
        }
        return errors
    }

    private static func parseLines(_ value: String) -> [String] {
        value
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

/// Per-channel UI state for botSection (issues #491, #492): one instance
/// each for webex and telegram, so the two near-identical sections share a
/// single view/controller implementation instead of being hand-duplicated.
private struct BotChannelUIState {
    var tokenInput = ""
    var tokenStatus = BotTokenStatus(agent: "", channel: "", configured: false, secretName: nil, allowedUsers: [])
    var serviceStatus: BotServiceStatus?
    var isLoading = false
    var isSavingToken = false
    var isRestarting = false
    var status: String?
    var statusIsError = false

    var showLogs = false
    var isLoadingLogs = false
    var logLines: [String] = []
    var logsError: String?
}

/// Recent journalctl output for one agent's bot listener (issue #492).
private struct BotLogsSheet: View {
    let title: String
    let channel: String
    @Binding var state: BotChannelUIState
    let reload: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(title) Logs")
                    .weeFont(.title3, weight: .bold)
                    .foregroundStyle(WeeTheme.textPrimary)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    HStack(spacing: 6) {
                        if state.isLoadingLogs { ProgressView().controlSize(.small) }
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(WeeGhostButtonStyle())
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider().overlay(WeeTheme.divider)

            Group {
                if state.isLoadingLogs && state.logLines.isEmpty {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let logsError = state.logsError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .weeFont(size: 22)
                            .foregroundStyle(WeeTheme.danger)
                        Text(logsError)
                            .weeFont(.caption)
                            .foregroundStyle(WeeTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                } else if state.logLines.isEmpty {
                    Text("No recent log output.")
                        .weeFont(.caption)
                        .foregroundStyle(WeeTheme.textMuted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(state.logLines.joined(separator: "\n"))
                            .weeFont(.caption, design: .monospaced)
                            .foregroundStyle(WeeTheme.textPrimary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85))
        }
        .frame(width: 640, height: 440)
        .background(WeeTheme.background)
    }
}

private struct AgentEditorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .weeFont(.headline, weight: .semibold)
                .foregroundStyle(WeeTheme.textPrimary)

            content
        }
        .padding(13)
        .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct AgentEditorFieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .weeFont(.caption, weight: .semibold)
                .foregroundStyle(WeeTheme.textMuted)
                .textCase(.uppercase)

            content
                .textFieldStyle(.plain)
                .foregroundStyle(WeeTheme.textPrimary)
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct AgentEditorTextAreaRow: View {
    let title: String
    @Binding var text: String
    let minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .weeFont(.caption, weight: .semibold)
                .foregroundStyle(WeeTheme.textMuted)
                .textCase(.uppercase)

            TextEditor(text: $text)
                .weeFont(.footnote)
                .scrollContentBackground(.hidden)
                .foregroundStyle(WeeTheme.textPrimary)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

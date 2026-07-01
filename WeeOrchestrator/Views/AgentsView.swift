import SwiftUI

struct AgentsView: View {
    @Bindable var model: WeeAppModel
    @State private var editorContext: AgentEditorContext?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Agents")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WeeTheme.textPrimary)
                    Text("\(model.agents.count) configured")
                        .font(.caption)
                        .foregroundStyle(WeeTheme.textSecondary)
                }
                Spacer()
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
            .padding(14)
            .glassPanel()

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.agents) { agent in
                        AgentCard(
                            agent: agent,
                            isSelected: agent.name == model.selectedAgent,
                            onEdit: {
                                editorContext = AgentEditorContext(agentName: agent.name)
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.selectedAgent = agent.name
                            model.saveConfiguration()
                        }
                    }
                }
                .padding(14)
            }
            .scrollIndicators(.hidden)
            .glassPanel()
        }
        .padding(16)
        .sheet(item: $editorContext) { context in
            AgentEditorSheet(model: model, agentName: context.agentName)
                .frame(width: 760, height: 720)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(agent.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? WeeTheme.gold : WeeTheme.textPrimary)
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(WeeGhostButtonStyle())
                .help("Edit \(agent.name)")

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(WeeTheme.accent)
                }
            }

            Text(agent.description)
                .font(.subheadline)
                .foregroundStyle(WeeTheme.textSecondary)
                .lineLimit(3)

            HStack {
                if let runtime = agent.primaryRuntime {
                    StatusPill(text: runtime, color: WeeTheme.accent, symbol: "terminal")
                }
                if let model = agent.primaryModel {
                    StatusPill(text: model, color: WeeTheme.gold, symbol: "cpu")
                }
            }
        }
        .padding(14)
        .background(isSelected ? WeeTheme.accent.opacity(0.12) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(isSelected ? WeeTheme.accent.opacity(0.32) : WeeTheme.glassStroke))
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

    private let runtimeFallbacks = ["copilot", "copilot-sdk", "claude", "claude-sdk", "gemini", "opencode", "codex", "devin"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(agentName == nil ? "New Agent" : "Edit Agent")
                    .font(.title3.weight(.bold))
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
        .confirmationDialog("Delete Agent?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete \(selectedAgentName)", role: .destructive) {
                Task { await deleteSelectedAgent() }
            }
        } message: {
            Text("This removes the agent from the shared agents config.")
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.gold)
            }

            if let status {
                Text(status)
                    .font(.caption)
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

private struct AgentEditorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
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
                .font(.caption.weight(.semibold))
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
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeTheme.textMuted)
                .textCase(.uppercase)

            TextEditor(text: $text)
                .font(.footnote)
                .scrollContentBackground(.hidden)
                .foregroundStyle(WeeTheme.textPrimary)
                .frame(minHeight: minHeight)
                .padding(8)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

import SwiftUI

struct SettingsView: View {
    @Bindable var model: WeeAppModel
    let environment: WeeEnvironment
    @State private var testResult: String?
    @State private var telegramIdentity = ""
    @State private var pairingCode = ""
    @State private var showManualToken = false
    @State private var advancedServiceExpanded = false
    @State private var hasLoadedWebSettings = false
    @State private var agentsConfig: AgentsConfigResponse?
    @State private var selectedAgentName = ""
    @State private var draftAgent = AgentConfiguration()
    @State private var originalAgent = AgentConfiguration()
    @State private var settingsStatus: String?
    @State private var settingsStatusIsError = false
    @State private var envContent = ""
    @State private var envStatus: String?
    @State private var envStatusIsError = false
    @State private var notificationsEnabled = true
    @State private var showDeleteConfirmation = false
    @State private var connectorAgent = ""
    @State private var connectorChannel = "telegram"
    @State private var connectorToken = ""
    @State private var connectorAllowedUsers = ""
    @State private var connectorStatus: String?
    @State private var connectorConfigured = false
    @State private var showRemoveConnectorConfirmation = false
    @State private var showCloneConfirmation = false
    @State private var showPullConfirmation = false
    @State private var localCatalogRuntime = "claude"
    @State private var localCatalogModelText = ""

    private let runtimeFallbacks = ["copilot", "copilot-sdk", "claude", "claude-sdk", "gemini", "opencode", "codex", "devin"]

    var body: some View {
        VStack(spacing: 8) {
            PageHeader(title: "\(environment.title) Settings", subtitle: pageSubtitle, symbol: environment.symbol) {
                StatusPill(
                    text: model.isAuthenticated ? "authenticated" : "sign-in required",
                    color: model.isAuthenticated ? WeeTheme.emerald : WeeTheme.gold,
                    symbol: model.isAuthenticated ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                )
            }

            ScrollView {
                VStack(spacing: 8) {
                    connectionSection
                    if environment == .local {
                        localSourceSection
                        localKanbanRepositorySection
                        localModelCatalogSection
                        localWeeRuntimeSection
                        localServiceSection
                    }
                    connectorSection
                    if environment == .remote { telegramAuthSection }
                    advancedTokenSection
                    environmentSection
                    connectionSummary
                }
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .padding(10)
        .task {
            await model.switchEnvironment(to: environment)
            if telegramIdentity.isEmpty {
                telegramIdentity = model.configuration.identity
            }
            connectorAgent = model.agents.first?.name ?? model.selectedAgent
            await loadWebSettingsIfNeeded()
            await loadConnectorStatus()
            loadLocalCatalogModels()
            if environment == .local {
                await model.loadLocalKanbanSettings()
            }
        }
        .confirmationDialog("Delete Agent?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete \(selectedAgentName)", role: .destructive) {
                Task { await deleteSelectedAgent() }
            }
        } message: {
            Text("This removes the agent from the shared agents config.")
        }
        .confirmationDialog("Remove \(connectorChannel.capitalized) Connection?", isPresented: $showRemoveConnectorConfirmation, titleVisibility: .visible) {
            Button("Remove token", role: .destructive) {
                Task { await deleteConnector() }
            }
        } message: {
            Text("This removes the bot token for \(connectorAgent) from the \(environment.title) API secure store.")
        }
        .confirmationDialog("Clone Local API?", isPresented: $showCloneConfirmation, titleVisibility: .visible) {
            Button("Clone") {
                Task { await model.cloneLocalAPISource() }
            }
        } message: {
            Text("This will clone the configured repository into the selected folder. The folder must be empty or not exist.")
        }
        .confirmationDialog("Pull Latest API Source?", isPresented: $showPullConfirmation, titleVisibility: .visible) {
            Button("Pull Latest") {
                Task { await model.pullLatestLocalAPISource() }
            }
        } message: {
            Text("This will run git pull --ff-only in the configured local checkout. It will not overwrite local commits or force-reset files.")
        }
    }

    private var advancedTokenSection: some View {
        SettingsSectionBox(title: "Advanced Access", systemImage: "key.fill") {
            manualTokenSection
        }
    }

    private var pageSubtitle: String {
        environment == .local
            ? "Run and configure the API and agents on this Mac"
            : "Connect to and configure your remote Wee environment"
    }

    private var connectionSection: some View {
        SettingsSectionBox(title: "\(model.activeEnvironment.title) API", systemImage: model.activeEnvironment.symbol) {
            FieldRow(title: "Backend URL") {
                TextField("https://host:8000", text: $model.configuration.baseURLString)
            }

            Toggle("Allow insecure TLS", isOn: $model.configuration.allowInsecureTLS)
                .tint(WeeTheme.accent)
                .foregroundStyle(WeeTheme.textPrimary)

            Toggle("Enable task notifications", isOn: notificationToggle)
                .tint(WeeTheme.accent)
                .foregroundStyle(WeeTheme.textPrimary)

            HStack {
                Button {
                    model.saveConfiguration()
                    testResult = "Saved"
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .keyboardShortcut("s", modifiers: .command)

                Button {
                    Task {
                        model.saveConfiguration()
                        await model.refreshAll()
                        testResult = model.errorMessage == nil ? "Connected" : model.errorMessage
                    }
                } label: {
                    Label("Test", systemImage: "network")
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(testResult == "Connected" || testResult == "Saved" ? WeeTheme.accent : WeeTheme.danger)
            }
        }
    }

    private var localServiceSection: some View {
        SettingsSectionBox(title: "Local API Service", systemImage: "terminal.fill") {
            HStack {
                StatusPill(
                    text: model.isLocalServiceRunning ? "running" : "stopped",
                    color: model.isLocalServiceRunning ? WeeTheme.emerald : WeeTheme.gold,
                    symbol: model.isLocalServiceRunning ? "play.circle.fill" : "stop.circle"
                )
                Text(model.localServiceStatus)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
                    .lineLimit(1)
            }

            FieldRow(title: "Executable") {
                TextField("/path/to/python3", text: $model.localServiceConfiguration.executablePath)
            }
            FieldRow(title: "Arguments") {
                TextField("agent_manager.py --port 8001", text: $model.localServiceConfiguration.arguments)
            }
            FieldRow(title: "Working Directory") {
                TextField("/path/to/Wee-Orchestrator", text: $model.localServiceConfiguration.workingDirectory)
            }

            Toggle("Start local API when Wee opens", isOn: $model.localServiceConfiguration.autoStart)
                .tint(WeeTheme.accent)

            HStack {
                Button {
                    Task {
                        model.saveConfiguration()
                        await model.startLocalAPI()
                    }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(model.isLocalServiceRunning)

                Button {
                    model.stopLocalAPI()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(!model.isLocalServiceRunning)

                Button {
                    model.saveConfiguration()
                    model.restartLocalAPI()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            if !model.localServiceLog.isEmpty {
                DisclosureGroup("Recent service output") {
                    ScrollView {
                        Text(model.localServiceLog)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(WeeTheme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .padding(8)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7))
                }
            }

            Text("The local service runs only the executable and arguments configured above. It is never enabled automatically unless you opt in.")
                .font(.caption)
                .foregroundStyle(WeeTheme.gold)
        }
    }

    private var localWeeRuntimeSection: some View {
        SettingsSectionBox(title: "Wee Runtime", systemImage: "sparkles") {
            HStack {
                StatusPill(
                    text: model.localOpenRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "OpenRouter key not set" : "OpenRouter key configured",
                    color: model.localOpenRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? WeeTheme.gold : WeeTheme.emerald,
                    symbol: model.localOpenRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "key" : "checkmark.shield.fill"
                )
                Spacer()
            }

            FieldRow(title: "OpenRouter API Key") {
                SecureField("sk-or-v1-…", text: $model.localOpenRouterAPIKey)
            }

            HStack {
                Button {
                    model.saveConfiguration()
                    if model.isLocalServiceRunning { model.restartLocalAPI() }
                    testResult = model.isLocalServiceRunning
                        ? "OpenRouter key saved; local API restarting"
                        : "OpenRouter key saved"
                } label: {
                    Label("Save Runtime Key", systemImage: "key.fill")
                }
                .buttonStyle(WeePrimaryButtonStyle())

                if !model.localOpenRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(role: .destructive) {
                        model.localOpenRouterAPIKey = ""
                        model.saveConfiguration()
                        if model.isLocalServiceRunning { model.restartLocalAPI() }
                        testResult = "OpenRouter key removed"
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(WeeGhostButtonStyle())
                }
            }

            Text("This key is stored only in this Mac’s Keychain and is passed directly to the locally managed API. Save while the service is running to restart it with the new key.")
                .font(.caption)
                .foregroundStyle(WeeTheme.textMuted)
        }
    }

    private var localModelCatalogSection: some View {
        SettingsSectionBox(title: "Local API Model Catalog", systemImage: "list.bullet.rectangle") {
            Text("Maintain the model options offered by this Mac’s local API. Enter one model ID per line; duplicate and blank entries are removed when you save.")
                .font(.caption)
                .foregroundStyle(WeeTheme.textSecondary)

            Picker("Runtime", selection: $localCatalogRuntime) {
                ForEach(model.localModelManifestRuntimes, id: \.self) { runtime in
                    Text(runtime.capitalized).tag(runtime)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: localCatalogRuntime) { _, _ in loadLocalCatalogModels() }

            TextEditor(text: $localCatalogModelText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7))

            HStack {
                Button {
                    Task {
                        let entries = localCatalogModelText.components(separatedBy: .newlines)
                        if await model.saveLocalModelManifest(runtime: localCatalogRuntime, models: entries) {
                            localCatalogModelText = model.loadLocalModelManifest(runtime: localCatalogRuntime).joined(separator: "\n")
                        }
                    }
                } label: {
                    Label("Save Model List", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WeePrimaryButtonStyle())

                Button {
                    loadLocalCatalogModels()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WeeGhostButtonStyle())
            }

            if !model.localModelManifestStatus.isEmpty {
                Text(model.localModelManifestStatus)
                    .font(.caption)
                    .foregroundStyle(model.localModelManifestStatus.localizedCaseInsensitiveContains("could not") || model.localModelManifestStatus.localizedCaseInsensitiveContains("add at least") ? WeeTheme.danger : WeeTheme.textMuted)
            }

            Text("This edits every configured local runtime except Wee, whose catalog is discovered dynamically from Ollama and OpenRouter. It never changes the Remote API or account access.")
                .font(.caption)
                .foregroundStyle(WeeTheme.textMuted)
        }
    }

    private func loadLocalCatalogModels() {
        localCatalogModelText = model.loadLocalModelManifest(runtime: localCatalogRuntime).joined(separator: "\n")
        if !model.localModelManifestRuntimes.contains(localCatalogRuntime),
           let firstRuntime = model.localModelManifestRuntimes.first {
            localCatalogRuntime = firstRuntime
            localCatalogModelText = model.loadLocalModelManifest(runtime: firstRuntime).joined(separator: "\n")
        }
    }

    private var localSourceSection: some View {
        SettingsSectionBox(title: "API Source", systemImage: "arrow.down.doc") {
            Text("Install or update the local Wee API before starting the service.")
                .font(.caption)
                .foregroundStyle(WeeTheme.textSecondary)

            FieldRow(title: "Repository") {
                TextField("https://github.com/owner/repo.git", text: $model.localServiceConfiguration.repositoryURL)
            }
            FieldRow(title: "Checkout Folder") {
                TextField("~/Developer/Wee-Orchestrator", text: $model.localServiceConfiguration.checkoutDirectory)
            }

            HStack {
                Button {
                    model.saveConfiguration()
                    showCloneConfirmation = true
                } label: {
                    Label("Clone", systemImage: "arrow.down.to.line.compact")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(model.isLocalSourceWorking)

                Button {
                    model.saveConfiguration()
                    showPullConfirmation = true
                } label: {
                    Label("Pull Latest", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(model.isLocalSourceWorking)

                if model.isLocalSourceWorking {
                    ProgressView().controlSize(.small).tint(WeeTheme.accent)
                }
            }

            Text(model.localSourceStatus)
                .font(.caption.weight(.semibold))
                .foregroundStyle(model.localSourceStatus.localizedCaseInsensitiveContains("failed") ? WeeTheme.danger : WeeTheme.textSecondary)

            if !model.localSourceOutput.isEmpty {
                DisclosureGroup("Git output") {
                    ScrollView {
                        Text(model.localSourceOutput)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(WeeTheme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                    .padding(8)
                    .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }

    private var localKanbanRepositorySection: some View {
        SettingsSectionBox(title: "TODO Kanban", systemImage: "rectangle.3.group.bubble") {
            Text("Choose the GitHub repository whose issues are shown on this Mac's Kanban board.")
                .font(.caption)
                .foregroundStyle(WeeTheme.textSecondary)

            FieldRow(title: "Repository") {
                TextField("owner/repository", text: $model.localKanbanRepository)
            }

            HStack(spacing: 8) {
                Button {
                    Task { _ = await model.saveLocalKanbanSettings() }
                } label: {
                    Label("Save Repository", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(model.isSavingLocalKanbanSettings)

                Button {
                    Task { await model.loadLocalKanbanSettings() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(model.isSavingLocalKanbanSettings)

                if model.isSavingLocalKanbanSettings {
                    ProgressView().controlSize(.small).tint(WeeTheme.accent)
                }
            }

            if !model.localKanbanEffectiveRepository.isEmpty {
                LabeledContent("Active repository") {
                    Text(model.localKanbanEffectiveRepository)
                        .font(.caption.monospaced())
                        .foregroundStyle(WeeTheme.textPrimary)
                        .textSelection(.enabled)
                }
            }

            Text("Use `owner/repository`. Leave the field empty and save to use the Git remote from the local API checkout\(model.localKanbanFallbackRepository.isEmpty ? "." : " (currently \(model.localKanbanFallbackRepository)).")")
                .font(.caption)
                .foregroundStyle(WeeTheme.textMuted)

            if !model.localKanbanSettingsStatus.isEmpty {
                Text(model.localKanbanSettingsStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.localKanbanSettingsStatus.localizedCaseInsensitiveContains("invalid") || model.localKanbanSettingsStatus.localizedCaseInsensitiveContains("failed") || model.localKanbanSettingsStatus.localizedCaseInsensitiveContains("error") ? WeeTheme.danger : WeeTheme.textSecondary)
            }
        }
    }

    private var connectorSection: some View {
        SettingsSectionBox(title: "Telegram & Webex", systemImage: "antenna.radiowaves.left.and.right") {
            Picker("Agent", selection: $connectorAgent) {
                ForEach(model.agents) { agent in Text(agent.name).tag(agent.name) }
            }
            .onChange(of: connectorAgent) { Task { await loadConnectorStatus() } }

            Picker("Channel", selection: $connectorChannel) {
                Text("Telegram").tag("telegram")
                Text("Webex").tag("webex")
            }
            .pickerStyle(.segmented)
            .onChange(of: connectorChannel) { Task { await loadConnectorStatus() } }

            HStack {
                StatusPill(
                    text: connectorConfigured ? "configured" : "not configured",
                    color: connectorConfigured ? WeeTheme.emerald : WeeTheme.gold,
                    symbol: connectorConfigured ? "checkmark.shield.fill" : "exclamationmark.shield"
                )
                Text(model.activeEnvironment.title)
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textMuted)
            }

            FieldRow(title: "Bot Token") {
                SecureField(connectorConfigured ? "Enter replacement token" : "Required", text: $connectorToken)
            }
            TextAreaRow(title: "Allowed Users", text: $connectorAllowedUsers, minHeight: 58)

            HStack {
                Button {
                    Task { await saveConnector() }
                } label: {
                    Label("Save Connection", systemImage: "lock.shield.fill")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(connectorAgent.isEmpty || connectorToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(role: .destructive) {
                    showRemoveConnectorConfirmation = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(!connectorConfigured)
            }

            Text("Tokens are sent directly to the selected Wee API and stored by its secure secret store; they are never written to app preferences.")
                .font(.caption)
                .foregroundStyle(WeeTheme.textMuted)

            if let connectorStatus {
                Text(connectorStatus)
                    .font(.caption)
                    .foregroundStyle(connectorStatus.localizedCaseInsensitiveContains("failed") ? WeeTheme.danger : WeeTheme.accent)
            }
        }
    }

    private var telegramAuthSection: some View {
        SettingsSectionBox(title: "Telegram Sign In", systemImage: "paperplane.circle.fill") {
            HStack {
                StatusPill(
                    text: model.isAuthenticated ? "signed in" : "required",
                    color: model.isAuthenticated ? WeeTheme.accent : WeeTheme.gold
                )
                Spacer()
            }

            if model.isAuthenticated {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.configuration.identity.isEmpty ? "Authenticated" : model.configuration.identity)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WeeTheme.textPrimary)
                        .lineLimit(1)

                    Button {
                        model.signOut()
                        testResult = nil
                        pairingCode = ""
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(WeeGhostButtonStyle())
                }
            } else {
                FieldRow(title: "Telegram Username") {
                    TextField("@username", text: $telegramIdentity)
                }

                Button {
                    Task {
                        await model.requestTelegramPairing(identity: telegramIdentity)
                    }
                } label: {
                    Label("Send Pairing Code", systemImage: "paperplane")
                }
                .buttonStyle(WeePrimaryButtonStyle())
                .disabled(model.isLoading || telegramIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if model.authPairingIdentity != nil {
                    FieldRow(title: "Pairing Code") {
                        TextField("123456", text: $pairingCode)
                            .onChange(of: pairingCode) {
                                pairingCode = String(pairingCode.filter(\.isNumber).prefix(6))
                            }
                    }

                    Button {
                        Task {
                            await model.verifyTelegramPairing(code: pairingCode)
                            if model.isAuthenticated {
                                pairingCode = ""
                                testResult = "Connected"
                            }
                        }
                    } label: {
                        Label("Verify", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(WeePrimaryButtonStyle())
                    .disabled(model.isLoading || pairingCode.count < 6)
                }
            }

            if let authStatus = model.authStatusMessage {
                Text(authStatus)
                    .font(.caption)
                    .foregroundStyle(authStatus.localizedCaseInsensitiveContains("signed in") || authStatus.localizedCaseInsensitiveContains("sent") ? WeeTheme.accent : WeeTheme.danger)
            }
        }
    }

    private var manualTokenSection: some View {
        DisclosureGroup(isExpanded: $showManualToken) {
            VStack(spacing: 12) {
                FieldRow(title: "Bearer Token") {
                    SecureField("Token", text: $model.configuration.token)
                }

                FieldRow(title: "Identity") {
                    TextField("user identity", text: $model.configuration.identity)
                }

                FieldRow(title: "Channel") {
                    Picker("Channel", selection: $model.configuration.channel) {
                        Text("telegram").tag("telegram")
                        Text("webex").tag("webex")
                        Text("webui").tag("webui")
                    }
                    .pickerStyle(.segmented)
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Advanced Token", systemImage: "key")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(WeeTheme.textSecondary)
        }
        .tint(WeeTheme.accent)
    }

    private var agentSettingsSection: some View {
        SettingsSectionBox(title: "\(model.activeEnvironment.title) Agent Settings", systemImage: "person.3.fill") {
            HStack {
                Picker("Agent", selection: selectedAgentBinding) {
                    ForEach(agentsConfig?.agents.map(\.name) ?? [], id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .disabled(agentsConfig?.agents.isEmpty ?? true)

                Button {
                    addAgent()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(WeeGhostButtonStyle())

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(WeeGhostButtonStyle())
                .disabled(selectedAgentName.isEmpty)
            }

            FieldRow(title: "Name") {
                TextField("agent-name", text: $draftAgent.name)
            }

            FieldRow(title: "Working Path") {
                TextField("/opt/my-agent", text: $draftAgent.path)
            }

            TextAreaRow(title: "Description", text: optionalTextBinding(\.description), minHeight: 74)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                FieldRow(title: "Primary Runtime") {
                    Picker("Primary Runtime", selection: optionalTextBinding(\.primaryRuntime)) {
                        Text("Default").tag("")
                        ForEach(runtimeOptions, id: \.self) { runtime in
                            Text(runtime).tag(runtime)
                        }
                    }
                }

                FieldRow(title: "Primary Model") {
                    TextField("e.g. claude-sonnet-4.6", text: optionalTextBinding(\.primaryModel))
                }

                FieldRow(title: "Fallback Runtime") {
                    Picker("Fallback Runtime", selection: optionalTextBinding(\.fallbackRuntime)) {
                        Text("None").tag("")
                        ForEach(runtimeOptions, id: \.self) { runtime in
                            Text(runtime).tag(runtime)
                        }
                    }
                }

                FieldRow(title: "Fallback Model") {
                    TextField("e.g. gpt-4-turbo", text: optionalTextBinding(\.fallbackModel))
                }

                FieldRow(title: "Max Concurrent Tasks") {
                    TextField("1", text: maxConcurrentBinding)
                }
            }

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

            if draftAgent != originalAgent {
                Text("Unsaved agent changes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WeeTheme.gold)
            }

            if let settingsStatus {
                Text(settingsStatus)
                    .font(.caption)
                    .foregroundStyle(settingsStatusIsError ? WeeTheme.danger : WeeTheme.accent)
            }
        }
    }

    private var permissionsSection: some View {
        SettingsSectionBox(title: "Permissions", systemImage: "lock.shield.fill") {
            FieldRow(title: "Mode") {
                Picker("Mode", selection: $draftAgent.permissions.mode) {
                    Text("elevated - full access").tag("elevated")
                    Text("restricted - curated tools").tag("restricted")
                    Text("sandboxed - no external access").tag("sandboxed")
                }
            }

            DisclosureGroup("Directories") {
                VStack(spacing: 10) {
                    TextAreaRow(title: "Allow Read", text: allowReadBinding, minHeight: 70)
                    TextAreaRow(title: "Allow Write", text: allowWriteBinding, minHeight: 70)
                    TextAreaRow(title: "Deny", text: directoryDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }

            DisclosureGroup("Tools") {
                VStack(spacing: 10) {
                    TextAreaRow(title: "Allow", text: toolsAllowBinding, minHeight: 70)
                    TextAreaRow(title: "Deny", text: toolsDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }

            DisclosureGroup("Network") {
                VStack(spacing: 10) {
                    TextAreaRow(title: "Allow URLs", text: networkAllowBinding, minHeight: 70)
                    TextAreaRow(title: "Deny URLs", text: networkDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }

            DisclosureGroup("MCP Servers") {
                VStack(spacing: 10) {
                    TextAreaRow(title: "Allow", text: mcpAllowBinding, minHeight: 70)
                    TextAreaRow(title: "Deny", text: mcpDenyBinding, minHeight: 70)
                }
                .padding(.top, 8)
            }
        }
    }

    private var environmentSection: some View {
        SettingsSectionBox(title: "Advanced Service Configuration", systemImage: "wrench.and.screwdriver") {
            DisclosureGroup("Edit API environment and restart services", isExpanded: $advancedServiceExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    TextAreaRow(title: ".env", text: $envContent, minHeight: 220)

                    HStack {
                        Button {
                            Task { await loadEnvFile() }
                        } label: {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(WeeGhostButtonStyle())

                        Button {
                            Task { await saveEnvFile() }
                        } label: {
                            Label("Save .env", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(WeePrimaryButtonStyle())

                        Button(role: .destructive) {
                            Task { await restartServices() }
                        } label: {
                            Label("Restart Services", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(WeeGhostButtonStyle())
                    }

                    Text("Changes to .env require a service restart to take effect.")
                        .font(.caption)
                        .foregroundStyle(WeeTheme.gold)

                    if let envStatus {
                        Text(envStatus)
                            .font(.caption)
                            .foregroundStyle(envStatusIsError ? WeeTheme.danger : WeeTheme.accent)
                    }
                }
                .padding(.top, 8)
            }
            .onChange(of: advancedServiceExpanded) {
                if advancedServiceExpanded { Task { await loadEnvFile() } }
            }
        }
    }

    private var connectionSummary: some View {
        SettingsSectionBox(title: "Status", systemImage: "waveform.path.ecg") {
            HStack {
                StatusPill(text: model.health?.status ?? "unknown", color: model.health?.status == "ok" ? WeeTheme.accent : WeeTheme.gold)
                if let environment = model.health?.environment ?? model.appConfig?.appEnv {
                    StatusPill(text: environment, color: WeeTheme.gold)
                }
            }

            if let loaded = model.health?.agentsLoaded {
                Text("\(loaded) agents loaded")
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textSecondary)
            }

            if let lastRefresh = model.lastRefresh {
                Text(lastRefresh.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(WeeTheme.textMuted)
            }
        }
    }

    private var selectedAgentBinding: Binding<String> {
        Binding(
            get: { selectedAgentName },
            set: { selectAgent(named: $0) }
        )
    }

    private var notificationToggle: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { newValue in
                notificationsEnabled = newValue
                Task { await saveNotificationToggle(enabled: newValue) }
            }
        )
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
        Array(Set(runtimeFallbacks + model.availableRuntimes.map(\.id) + model.agents.compactMap(\.primaryRuntime))).sorted()
    }

    private var allowReadBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.directories.allowRead },
            set: { draftAgent.permissions.directories.allowRead = $0 }
        )
    }

    private var allowWriteBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.directories.allowWrite },
            set: { draftAgent.permissions.directories.allowWrite = $0 }
        )
    }

    private var directoryDenyBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.directories.deny },
            set: { draftAgent.permissions.directories.deny = $0 }
        )
    }

    private var toolsAllowBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.tools.allow },
            set: { draftAgent.permissions.tools.allow = $0 }
        )
    }

    private var toolsDenyBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.tools.deny },
            set: { draftAgent.permissions.tools.deny = $0 }
        )
    }

    private var networkAllowBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.network.allowURLs },
            set: { draftAgent.permissions.network.allowURLs = $0 }
        )
    }

    private var networkDenyBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.network.denyURLs },
            set: { draftAgent.permissions.network.denyURLs = $0 }
        )
    }

    private var mcpAllowBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.mcp.allow },
            set: { draftAgent.permissions.mcp.allow = $0 }
        )
    }

    private var mcpDenyBinding: Binding<String> {
        arrayBinding(
            get: { draftAgent.permissions.mcp.deny },
            set: { draftAgent.permissions.mcp.deny = $0 }
        )
    }

    private func loadWebSettingsIfNeeded(force: Bool = false) async {
        guard force || !hasLoadedWebSettings else { return }
        hasLoadedWebSettings = true
        await loadNotificationToggle()
    }

    private func loadConnectorStatus() async {
        guard !connectorAgent.isEmpty else {
            connectorConfigured = false
            connectorStatus = model.agents.isEmpty ? "No agents are available in this environment." : nil
            return
        }
        do {
            let response = try await model.client.botTokenStatus(agent: connectorAgent, channel: connectorChannel)
            connectorConfigured = response.configured
            connectorAllowedUsers = response.allowedUsers.joined(separator: "\n")
            connectorStatus = nil
        } catch {
            connectorConfigured = false
            connectorStatus = "Status unavailable: \(error.localizedDescription)"
        }
    }

    private func saveConnector() async {
        let token = connectorToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !connectorAgent.isEmpty, !token.isEmpty else { return }
        let users = connectorAllowedUsers
            .split(whereSeparator: { $0.isNewline || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            try await model.client.saveBotToken(agent: connectorAgent, channel: connectorChannel, token: token, allowedUsers: users)
            connectorToken = ""
            connectorConfigured = true
            connectorStatus = "\(connectorChannel.capitalized) configured for \(connectorAgent) on \(model.activeEnvironment.title)."
        } catch {
            connectorStatus = "Save failed: \(error.localizedDescription)"
        }
    }

    private func deleteConnector() async {
        do {
            try await model.client.deleteBotToken(agent: connectorAgent, channel: connectorChannel)
            connectorToken = ""
            connectorConfigured = false
            connectorStatus = "\(connectorChannel.capitalized) connection removed."
        } catch {
            connectorStatus = "Remove failed: \(error.localizedDescription)"
        }
    }

    private func loadAgentSettings() async {
        do {
            let config = try await model.client.agentsConfig()
            agentsConfig = config
            if let first = config.agents.first {
                let preferred = config.agents.contains(where: { $0.name == selectedAgentName }) ? selectedAgentName : first.name
                selectAgent(named: preferred)
            } else {
                selectedAgentName = ""
                draftAgent = AgentConfiguration()
                originalAgent = AgentConfiguration()
            }
            settingsStatus = nil
        } catch {
            settingsStatus = "Failed to load agents: \(error.localizedDescription)"
            settingsStatusIsError = true
        }
    }

    private func selectAgent(named name: String) {
        guard let agent = agentsConfig?.agents.first(where: { $0.name == name }) else { return }
        selectedAgentName = agent.name
        draftAgent = agent
        originalAgent = agent
    }

    private func addAgent() {
        var config = agentsConfig ?? AgentsConfigResponse(agents: [])
        let base = "new-agent"
        var candidate = base
        var index = 2
        while config.agents.contains(where: { $0.name == candidate }) {
            candidate = "\(base)-\(index)"
            index += 1
        }
        let agent = AgentConfiguration(name: candidate, path: "/opt/")
        config.agents.append(agent)
        agentsConfig = config
        selectedAgentName = agent.name
        draftAgent = agent
        originalAgent = AgentConfiguration()
        settingsStatus = "New agent ready. Save to write it to the shared config."
        settingsStatusIsError = false
    }

    private func saveAgentSettings() async {
        let errors = validate(draftAgent)
        guard errors.isEmpty else {
            settingsStatus = errors.joined(separator: " ")
            settingsStatusIsError = true
            return
        }

        var config = agentsConfig ?? AgentsConfigResponse(agents: [])
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
            settingsStatus = "Agent settings saved."
            settingsStatusIsError = false
            await model.refreshAll()
        } catch {
            settingsStatus = "Save failed: \(error.localizedDescription)"
            settingsStatusIsError = true
        }
    }

    private func discardAgentChanges() {
        draftAgent = originalAgent
        settingsStatus = "Discarded local edits."
        settingsStatusIsError = false
    }

    private func reloadAgents() async {
        do {
            try await model.client.reloadAgents()
            settingsStatus = "Agents reloaded in memory."
            settingsStatusIsError = false
            await model.refreshAll()
        } catch {
            settingsStatus = "Reload failed: \(error.localizedDescription)"
            settingsStatusIsError = true
        }
    }

    private func deleteSelectedAgent() async {
        guard !selectedAgentName.isEmpty, var config = agentsConfig else { return }
        config.agents.removeAll { $0.name == selectedAgentName }

        do {
            try await model.client.saveAgentsConfig(config)
            agentsConfig = config
            if let first = config.agents.first {
                selectAgent(named: first.name)
            } else {
                selectedAgentName = ""
                draftAgent = AgentConfiguration()
                originalAgent = AgentConfiguration()
            }
            settingsStatus = "Agent deleted."
            settingsStatusIsError = false
            await model.refreshAll()
        } catch {
            settingsStatus = "Delete failed: \(error.localizedDescription)"
            settingsStatusIsError = true
        }
    }

    private func loadEnvFile() async {
        do {
            let response = try await model.client.envSettings()
            envContent = response.content ?? ""
            envStatus = response.exists == false ? "No .env exists yet. Saving will create one." : nil
            envStatusIsError = false
        } catch {
            envStatus = "Failed to load .env: \(error.localizedDescription)"
            envStatusIsError = true
        }
    }

    private func saveEnvFile() async {
        do {
            _ = try await model.client.saveEnvSettings(envContent)
            envStatus = ".env saved."
            envStatusIsError = false
        } catch {
            envStatus = "Failed to save .env: \(error.localizedDescription)"
            envStatusIsError = true
        }
    }

    private func restartServices() async {
        do {
            let response = try await model.client.restartServices()
            if let results = response.results, !results.isEmpty {
                envStatus = results.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "\n")
            } else {
                envStatus = response.message ?? "Restart requested."
            }
            envStatusIsError = false
        } catch {
            envStatus = "Restart request sent. The API may reconnect shortly."
            envStatusIsError = false
        }
    }

    private func loadNotificationToggle() async {
        do {
            notificationsEnabled = try await model.client.notificationSettings().notificationsEnabled
        } catch {
            settingsStatus = "Notification setting unavailable: \(error.localizedDescription)"
            settingsStatusIsError = true
        }
    }

    private func saveNotificationToggle(enabled: Bool) async {
        do {
            notificationsEnabled = try await model.client.saveNotificationSettings(enabled: enabled).notificationsEnabled
        } catch {
            settingsStatus = "Notification save failed: \(error.localizedDescription)"
            settingsStatusIsError = true
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

private struct SettingsSectionBox<Content: View>: View {
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
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeeTheme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(WeeTheme.glassStroke))
    }
}

private struct FieldRow<Content: View>: View {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
        }
    }
}

private struct TextAreaRow: View {
    let title: String
    @Binding var text: String
    var minHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(WeeTheme.textMuted)
                .textCase(.uppercase)

            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .foregroundStyle(WeeTheme.textPrimary)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: minHeight)
                .padding(8)
                .background(WeeTheme.sunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(WeeTheme.glassStroke))
        }
    }
}

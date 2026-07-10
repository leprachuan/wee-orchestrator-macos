import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class WeeAppModel {
    var configuration: APIConfiguration
    var health: HealthResponse?
    var appConfig: AppConfigResponse?
    var agents: [AgentSummary] = []
    var availableRuntimes: [RuntimeEntry] = []
    var availableModels: [ModelCatalogEntry] = []
    var tasks: [BackgroundTaskSummary] = []
    var scheduledJobs: [ScheduledJobSummary] = []
    var schedulerStatusMessage: String?
    var kanbanBoard: KanbanBoardResponse?
    var kanbanStatusMessage: String?
    var selectedTask: BackgroundTaskDetail?
    var historySessions: [HistorySessionSummary] = []
    var chatMessages: [ChatMessage] = [
        ChatMessage(role: .system, text: "Wee macOS client ready.")
    ]
    var selectedAgent: String = "orchestrator"
    var selectedRuntime: String = ""
    var selectedModel: String = ""
    var selectedPermissionMode: String = "restricted"
    var currentSessionID: String?
    var isLoading = false
    var errorMessage: String?
    var lastRefresh: Date?
    var authPairingIdentity: String?
    var authStatusMessage: String?

    private let defaults = UserDefaults.standard
    private var previousTaskStatuses: [String: String] = [:]

    init() {
        let storedToken = KeychainStore.loadToken()
        configuration = APIConfiguration(
            baseURLString: defaults.string(forKey: "wee.baseURL") ?? APIConfiguration.defaults.baseURLString,
            token: storedToken.isEmpty ? Self.launchToken : storedToken,
            identity: defaults.string(forKey: "wee.identity") ?? APIConfiguration.defaults.identity,
            channel: defaults.string(forKey: "wee.channel") ?? APIConfiguration.defaults.channel,
            allowInsecureTLS: defaults.object(forKey: "wee.allowInsecureTLS") as? Bool ?? APIConfiguration.defaults.allowInsecureTLS
        )
        selectedAgent = defaults.string(forKey: "wee.selectedAgent") ?? "orchestrator"
        selectedRuntime = defaults.string(forKey: "wee.selectedRuntime") ?? ""
        selectedModel = defaults.string(forKey: "wee.selectedModel") ?? ""
        selectedPermissionMode = defaults.string(forKey: "wee.selectedPermissionMode") ?? "restricted"
    }

    var client: WeeAPIClient {
        WeeAPIClient(configuration: configuration)
    }

    var isAuthenticated: Bool {
        hasAuthToken
    }

    func bootstrap() async {
        await requestNotificationPermission()
        await refreshAll(useMockOnFailure: true)
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func saveConfiguration() {
        defaults.set(configuration.baseURLString, forKey: "wee.baseURL")
        defaults.set(configuration.identity, forKey: "wee.identity")
        defaults.set(configuration.channel, forKey: "wee.channel")
        defaults.set(configuration.allowInsecureTLS, forKey: "wee.allowInsecureTLS")
        defaults.set(selectedAgent, forKey: "wee.selectedAgent")
        defaults.set(selectedRuntime, forKey: "wee.selectedRuntime")
        defaults.set(selectedModel, forKey: "wee.selectedModel")
        defaults.set(selectedPermissionMode, forKey: "wee.selectedPermissionMode")
        KeychainStore.saveToken(configuration.token)
    }

    func requestTelegramPairing(identity: String) async {
        let trimmed = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authStatusMessage = "Enter your Telegram username first."
            return
        }

        isLoading = true
        errorMessage = nil
        authStatusMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.requestPairing(identity: trimmed, channel: "telegram")
            let resolved = response.identityResolved ?? trimmed.replacingOccurrences(of: "@", with: "")
            authPairingIdentity = resolved
            configuration.identity = resolved
            configuration.channel = "telegram"
            defaults.set(resolved, forKey: "wee.identity")
            defaults.set("telegram", forKey: "wee.channel")
            if let expires = response.expiresIn {
                authStatusMessage = "Code sent in Telegram. It expires in \(expires / 60) minutes."
            } else {
                authStatusMessage = response.message
            }
        } catch {
            errorMessage = error.localizedDescription
            authStatusMessage = error.localizedDescription
        }
    }

    func verifyTelegramPairing(code: String) async {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            authStatusMessage = "Enter the 6-digit pairing code."
            return
        }
        guard let identity = authPairingIdentity ?? optionalIdentity else {
            authStatusMessage = "Send a pairing code first."
            return
        }

        isLoading = true
        errorMessage = nil
        authStatusMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.verifyPairing(identity: identity, code: trimmed)
            configuration.token = response.token
            configuration.identity = response.identity
            configuration.channel = response.channel
            authPairingIdentity = nil
            saveConfiguration()
            currentSessionID = nil
            authStatusMessage = "Signed in with Telegram."
            await refreshAll()
        } catch {
            errorMessage = error.localizedDescription
            authStatusMessage = error.localizedDescription
        }
    }

    func signOut() {
        configuration.token = ""
        currentSessionID = nil
        authPairingIdentity = nil
        saveConfiguration()
        tasks = []
        scheduledJobs = []
        schedulerStatusMessage = nil
        kanbanBoard = nil
        kanbanStatusMessage = nil
        historySessions = []
        availableRuntimes = []
        availableModels = []
        chatMessages = [ChatMessage(role: .system, text: "Signed out.")]
        authStatusMessage = "Signed out."
    }

    func refreshAll(useMockOnFailure: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let healthResponse = client.health()
            async let configResponse = client.appConfig()
            async let agentResponse = client.agents()

            health = try await healthResponse
            appConfig = try await configResponse
            agents = try await agentResponse
            if !agents.contains(where: { $0.name == selectedAgent }) {
                selectedAgent = agents.first?.name ?? "orchestrator"
            }
            applySelectionDefaults()

            if !configuration.token.isEmpty {
                async let runtimeResponse: [RuntimeEntry]? = try? client.runtimes()
                async let taskResponse: [BackgroundTaskSummary]? = try? client.backgroundTasks()
                async let sessionResponse: [HistorySessionSummary]? = try? client.historySessions()

                availableRuntimes = (await runtimeResponse ?? []).sorted { $0.id < $1.id }
                let newTasks = await taskResponse ?? []
                notifyCompletedTasks(old: tasks, new: newTasks)
                tasks = newTasks
                historySessions = await sessionResponse ?? []

                if availableRuntimes.isEmpty {
                    let agentRuntimes = Set(agents.compactMap(\.primaryRuntime)).sorted()
                    if !agentRuntimes.isEmpty {
                        availableRuntimes = agentRuntimes.map { RuntimeEntry(id: $0) }
                    }
                }

                applySelectionDefaults()
                await loadAvailableModels(for: selectedRuntime)
                await loadScheduledJobs()
                await loadKanbanBoard()
            }

            lastRefresh = Date()
            saveConfiguration()
        } catch {
            errorMessage = error.localizedDescription
            if useMockOnFailure {
                installMockData()
            }
        }
    }

    func ensureChatSession() async -> String? {
        if let currentSessionID { return currentSessionID }
        guard hasAuthToken else {
            errorMessage = "Authentication required. Add a bearer token in Settings first."
            return nil
        }

        do {
            let desiredAgent = selectedAgent
            let desiredRuntime = selectedRuntimeOrNil
            let desiredModel = selectedModelOrNil
            let session = try await client.createSession(agent: nil, model: nil, runtime: nil)
            currentSessionID = session.sessionID
            if let agent = session.agent, !agent.isEmpty { selectedAgent = agent }
            if let runtime = session.runtime, !runtime.isEmpty { selectedRuntime = runtime }
            if let model = session.model, !model.isEmpty { selectedModel = model }
            try await applyPendingSessionConfiguration(
                sessionID: session.sessionID,
                desiredAgent: desiredAgent,
                desiredRuntime: desiredRuntime,
                desiredModel: desiredModel
            )
            try await applySessionPermissionModeIfNeeded(sessionID: session.sessionID)
            saveConfiguration()
            return session.sessionID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func sendChat(_ prompt: String, attachments: [ChatAttachment] = []) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        guard hasAuthToken else {
            let message = "Authentication required. Add a bearer token in Settings, then click Save."
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
            return
        }

        chatMessages.append(ChatMessage(role: .user, text: trimmed, attachments: attachments))
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let sessionID: String
            if let currentSessionID {
                sessionID = currentSessionID
            } else {
                let desiredAgent = selectedAgent
                let desiredRuntime = selectedRuntimeOrNil
                let desiredModel = selectedModelOrNil
                let session = try await client.createSession(agent: nil, model: nil, runtime: nil)
                currentSessionID = session.sessionID
                if let agent = session.agent, !agent.isEmpty {
                    selectedAgent = agent
                }
                if let runtime = session.runtime, !runtime.isEmpty {
                    selectedRuntime = runtime
                }
                if let model = session.model, !model.isEmpty {
                    selectedModel = model
                }
                try await applyPendingSessionConfiguration(
                    sessionID: session.sessionID,
                    desiredAgent: desiredAgent,
                    desiredRuntime: desiredRuntime,
                    desiredModel: desiredModel
                )
                try await applySessionPermissionModeIfNeeded(sessionID: session.sessionID)
                sessionID = session.sessionID
            }

            for attachment in attachments {
                _ = try await client.uploadFile(
                    sessionID: sessionID,
                    data: attachment.data,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType
                )
            }

            let query = attachments.isEmpty ? trimmed : (trimmed.isEmpty ? "[Attached \(attachments.count) file(s)]" : trimmed)

            chatMessages.append(ChatMessage(role: .assistant, text: ""))
            let streamIndex = chatMessages.count - 1

            let bytes = try await client.stream(
                sessionID: sessionID,
                query: query,
                agent: nil,
                runtime: nil,
                model: nil
            )

            var rawStreamText = ""
            var lastActivityText = ""
            for try await line in bytes.lines {
                guard let json = streamPayload(from: line) else { continue }
                guard let data = json.data(using: .utf8),
                      let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }

                switch event.type {
                case "chunk":
                    if let text = event.text {
                        rawStreamText += text
                        let cleaned = preferredFinalStreamText(accumulated: rawStreamText, doneResponse: nil)
                        if !cleaned.isEmpty {
                            chatMessages[streamIndex].text = cleaned
                        }
                    }
                case "tool_call":
                    lastActivityText = streamActivityText(from: event)
                    if chatMessages[streamIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !lastActivityText.isEmpty {
                        chatMessages[streamIndex].text = lastActivityText
                    }
                case "done":
                    let finalText = preferredFinalStreamText(accumulated: rawStreamText, doneResponse: event.response)
                    if !finalText.isEmpty {
                        chatMessages[streamIndex].text = finalText
                    } else if chatMessages[streamIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !lastActivityText.isEmpty {
                        chatMessages[streamIndex].text = lastActivityText
                    }
                    if let runtime = event.runtime, !runtime.isEmpty {
                        selectedRuntime = runtime
                    }
                    if let model = event.model, !model.isEmpty {
                        selectedModel = model
                    }
                case "error":
                    let message = event.message ?? event.text ?? "Stream error"
                    chatMessages[streamIndex].text = message
                default:
                    break
                }
            }

            if chatMessages[streamIndex].text.isEmpty {
                let finalText = preferredFinalStreamText(accumulated: rawStreamText, doneResponse: nil)
                chatMessages[streamIndex].text = finalText.isEmpty ? lastActivityText : finalText
            }

            if chatMessages[streamIndex].text.isEmpty {
                chatMessages.remove(at: streamIndex)
            }

            saveConfiguration()
            await loadHistorySessions()
        } catch {
            let message = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
        }
    }

    func startNewChat() async {
        guard hasAuthToken else {
            let message = "Authentication required. Sign in with Telegram in Settings."
            errorMessage = message
            chatMessages = [ChatMessage(role: .system, text: message)]
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let desiredAgent = selectedAgent
            let desiredRuntime = selectedRuntimeOrNil
            let desiredModel = selectedModelOrNil
            let session = try await client.createSession(agent: nil, model: nil, runtime: nil)
            currentSessionID = session.sessionID
            if let agent = session.agent, !agent.isEmpty {
                selectedAgent = agent
            }
            if let runtime = session.runtime, !runtime.isEmpty {
                selectedRuntime = runtime
            }
            if let model = session.model, !model.isEmpty {
                selectedModel = model
            }
            try await applyPendingSessionConfiguration(
                sessionID: session.sessionID,
                desiredAgent: desiredAgent,
                desiredRuntime: desiredRuntime,
                desiredModel: desiredModel
            )
            try await applySessionPermissionModeIfNeeded(sessionID: session.sessionID)
            saveConfiguration()
            chatMessages = [ChatMessage(role: .system, text: "New chat ready.")]
            await loadHistorySessions()
        } catch {
            let message = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
        }
    }

    func loadHistorySessions() async {
        guard hasAuthToken else {
            historySessions = []
            return
        }

        do {
            historySessions = try await client.historySessions()
        } catch {
            historySessions = []
        }
    }

    func selectHistorySession(_ session: HistorySessionSummary) async {
        guard hasAuthToken else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.historyMessages(sessionID: session.sessionID)
            currentSessionID = session.sessionID
            if let agent = session.agent, !agent.isEmpty {
                selectedAgent = agent
                saveConfiguration()
            }
            chatMessages = response.messages.map(ChatMessage.init(historyMessage:))
            if chatMessages.isEmpty {
                chatMessages = [ChatMessage(role: .system, text: "This chat has no messages yet.")]
            }
            await refreshSessionStatus(sessionID: session.sessionID)
        } catch {
            let message = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
        }
    }

    func changeAgent(to agent: String) async {
        guard agent != selectedAgent else { return }
        guard agents.contains(where: { $0.name == agent }) else { return }

        if currentSessionID == nil {
            selectedAgent = agent
            applySelectionDefaults(forceModelRefresh: true)
            saveConfiguration()
            chatMessages.append(ChatMessage(role: .system, text: "Next chat will use \(agent) on \(selectedRuntime) / \(selectedModel)."))
            return
        }

        guard hasAuthToken else {
            selectedAgent = agent
            saveConfiguration()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let sessionID = currentSessionID ?? ""
            let response = try await client.execute(sessionID: sessionID, query: "/agent set \(agent)", agent: nil, runtime: nil, model: nil)
            selectedAgent = agent
            saveConfiguration()
            chatMessages.append(ChatMessage(role: .system, text: response.response))
            await refreshSessionStatus(sessionID: sessionID)
            await loadHistorySessions()
        } catch {
            let message = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
        }
    }

    func createBackgroundTask(prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard hasAuthToken else {
            errorMessage = "Authentication required. Add a bearer token in Settings, then click Save."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await client.createBackgroundTask(
                prompt: trimmed,
                agent: selectedAgent,
                runtime: selectedRuntimeOrNil,
                model: selectedModelOrNil,
                permissionMode: selectedPermissionMode
            )
            tasks = try await client.backgroundTasks()
            await loadScheduledJobs()
            lastRefresh = Date()
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
        }
    }

    func changeRuntime(to runtime: String) async {
        let trimmed = runtime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != selectedRuntime else { return }

        if currentSessionID == nil {
            selectedRuntime = trimmed
            await loadAvailableModels(for: trimmed)
            chatMessages.append(ChatMessage(role: .system, text: "Next chat will use \(selectedRuntime) / \(selectedModel)."))
            saveConfiguration()
            return
        }

        await runSessionConfigurationCommand(
            command: "/runtime set \(trimmed)",
            afterSuccess: { [weak self] in
                guard let self else { return }
                await self.refreshSessionStatus(sessionID: self.currentSessionID ?? "")
                await self.loadAvailableModels(for: self.selectedRuntime)
            }
        )
    }

    func changeModel(to model: String) async {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != selectedModel else { return }

        if currentSessionID == nil {
            selectedModel = trimmed
            chatMessages.append(ChatMessage(role: .system, text: "Next chat will use \(selectedRuntime) / \(selectedModel)."))
            saveConfiguration()
            return
        }

        let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
        await runSessionConfigurationCommand(
            command: "/model set \"\(escaped)\"",
            afterSuccess: { [weak self] in
                guard let self else { return }
                await self.refreshSessionStatus(sessionID: self.currentSessionID ?? "")
            }
        )
    }

    func toggleFullAccess() async {
        let newMode = selectedPermissionMode == "elevated" ? "restricted" : "elevated"

        if currentSessionID == nil {
            selectedPermissionMode = newMode
            saveConfiguration()
            let description = newMode == "elevated" ? "Full access will be enabled for the next chat." : "Next chat will use restricted access."
            chatMessages.append(ChatMessage(role: .system, text: description))
            return
        }

        await runSessionConfigurationCommand(
            command: "/mode \(newMode)",
            afterSuccess: { [weak self] in
                self?.selectedPermissionMode = newMode
            }
        )
    }

    func loadScheduledJobs() async {
        guard hasAuthToken else {
            scheduledJobs = []
            schedulerStatusMessage = "Sign in to view scheduled jobs."
            return
        }

        do {
            scheduledJobs = try await client.scheduledJobs()
            schedulerStatusMessage = scheduledJobs.isEmpty ? "No scheduled jobs returned by the backend." : nil
        } catch {
            scheduledJobs = []
            schedulerStatusMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
        }
    }

    func saveScheduledJob(_ request: ScheduledJobMutationRequest, id: String?) async throws {
        if let id {
            try await client.updateScheduledJob(id: id, job: request)
        } else {
            try await client.createScheduledJob(request)
        }
        await loadScheduledJobs()
        schedulerStatusMessage = id == nil ? "Scheduled task created." : "Scheduled task updated."
    }

    func loadKanbanBoard() async {
        guard hasAuthToken else {
            kanbanBoard = nil
            kanbanStatusMessage = "Sign in to view the Kanban board."
            return
        }

        do {
            let board = try await client.kanbanBoard()
            kanbanBoard = board
            kanbanStatusMessage = board.total == 0 ? "No Kanban cards returned by the backend." : nil
            await scheduleDueNotifications(for: board.dueCards)
        } catch {
            kanbanBoard = nil
            kanbanStatusMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
        }
    }

    func loadKanbanItem(id: String) async -> KanbanItemDetail? {
        do {
            return try await client.kanbanItem(id: id)
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return nil
        }
    }

    func updateKanbanItem(
        id: String,
        title: String,
        details: String,
        status: String,
        agent: String,
        due: String,
        priority: String,
        urgency: String,
        labels: [String] = []
    ) async -> KanbanItemDetail? {
        do {
            let item = try await client.updateKanbanItem(
                id: id,
                title: nilIfEmpty(title),
                details: details,
                status: nilIfEmpty(status),
                agent: agent.trimmingCharacters(in: .whitespacesAndNewlines),
                due: due.trimmingCharacters(in: .whitespacesAndNewlines),
                priority: nilIfEmpty(priority),
                urgency: nilIfEmpty(urgency),
                labels: labels
            )
            await loadKanbanBoard()
            return item
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return nil
        }
    }

    func commentKanbanItem(id: String, body: String) async -> KanbanItemDetail? {
        do {
            let item = try await client.commentKanbanItem(id: id, body: body)
            await loadKanbanBoard()
            return item
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return nil
        }
    }

    func completeKanbanItem(id: String) async -> KanbanItemDetail? {
        do {
            let item = try await client.completeKanbanItem(id: id)
            await loadKanbanBoard()
            return item
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return nil
        }
    }

    func closeKanbanItem(id: String) async -> KanbanItemDetail? {
        do {
            let item = try await client.closeKanbanItem(id: id)
            await loadKanbanBoard()
            return item
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return nil
        }
    }

    func dispatchKanbanItem(id: String, agent: String, prompt: String) async -> KanbanDispatchResponse? {
        do {
            let response = try await client.dispatchKanbanItem(
                id: id,
                agent: agent,
                prompt: nilIfEmpty(prompt)
            )
            await loadKanbanBoard()
            return response
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return nil
        }
    }

    func loadTaskDetail(_ task: BackgroundTaskSummary) async {
        isLoading = true
        defer { isLoading = false }

        do {
            selectedTask = try await client.backgroundTask(id: task.taskID)
        } catch {
            errorMessage = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
        }
    }

    func installMockData() {
        health = HealthResponse(
            status: "offline",
            uptimeSeconds: nil,
            version: "mock",
            environment: "LOCAL",
            agentsLoaded: 6,
            schedulerEnabled: true,
            activeSessions: 0
        )
        appConfig = AppConfigResponse(schedulerEnabled: true, backgroundTasksEnabled: true, appEnv: "LOCAL")
        agents = [
            AgentSummary(name: "orchestrator", description: "Main routing and coordination agent.", path: nil, primaryRuntime: "claude", primaryModel: "haiku"),
            AgentSummary(name: "wee-dev", description: "Wee Orchestrator feature development and validation.", path: nil, primaryRuntime: "claude", primaryModel: "sonnet"),
            AgentSummary(name: "wee-qa", description: "Independent QA validation for orchestrator changes.", path: nil, primaryRuntime: "codex", primaryModel: "gpt-5.5")
        ]
        tasks = [
            BackgroundTaskSummary(taskID: "bg_mock1", agent: "wee-dev", runtime: "claude", model: "sonnet", prompt: "Prepare macOS app starter", status: "running", createdAt: "local preview", completedAt: nil, error: nil, usedFallback: false, actualRuntime: nil, actualModel: nil),
            BackgroundTaskSummary(taskID: "bg_mock2", agent: "wee-qa", runtime: "codex", model: "gpt-5.5", prompt: "Review desktop layout", status: "queued", createdAt: "local preview", completedAt: nil, error: nil, usedFallback: false, actualRuntime: nil, actualModel: nil)
        ]
        scheduledJobs = [
            ScheduledJobSummary(id: "mock-heartbeat", name: "Heartbeat", agent: "orchestrator", runtime: "wee", model: nil, mode: "ai", permissionMode: "restricted", task: "Check runtime health", schedule: "every hour", cron: "0 * * * *", workingDir: nil, notify: true, fallbackRuntime: nil, fallbackModel: nil, recurring: true, createdAt: "local preview", nextRun: "local preview", lastRun: nil, enabled: true, retries: 0, timeout: 300)
        ]
        availableRuntimes = [RuntimeEntry(id: "claude"), RuntimeEntry(id: "codex"), RuntimeEntry(id: "wee", icon: "🍀")]
        availableModels = [
            ModelCatalogEntry(id: "haiku", label: "haiku", group: "Default"),
            ModelCatalogEntry(id: "sonnet", label: "sonnet", group: "Default")
        ]
        selectedRuntime = "claude"
        selectedModel = "haiku"
        selectedPermissionMode = "restricted"
        schedulerStatusMessage = nil
        kanbanBoard = KanbanBoardResponse(
            success: true,
            columns: [
                "todo": [
                    KanbanCard(id: "mock:1", title: "Plan family dashboard", source: "flatfile", status: "todo", agent: "family_knowledge", priority: "normal", urgency: "normal", due: nil, dueBucket: "none", isOverdue: false, labels: ["agent:family_knowledge"], details: "Mock card for local preview.", url: nil, createdAt: nil, updatedAt: nil, githubIssueNumber: nil)
                ],
                "ai-active": [
                    KanbanCard(id: "mock:2", title: "Build macOS Kanban view", source: "github", status: "ai-active", agent: "wee-dev", priority: "high", urgency: "urgent", due: "2026-06-18", dueBucket: "today", isOverdue: false, labels: ["agent:wee-dev", "urgent"], details: "Mock active card.", url: nil, createdAt: nil, updatedAt: nil, githubIssueNumber: 367)
                ],
                "done": [],
                "in-progress": [],
                "pending-review": []
            ],
            agents: ["family_knowledge", "wee-dev"],
            sources: ["flatfile", "github"],
            total: 2,
            repo: "leprachuan/Wee-Orchestrator"
        )
        kanbanStatusMessage = nil
        historySessions = [
            HistorySessionSummary(sessionID: "mock-chat", title: "Mock orchestration chat", preview: "Local preview session", agent: "orchestrator", createdAt: nil, updatedAt: nil)
        ]
        lastRefresh = Date()
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var selectedRuntimeOrNil: String? {
        nilIfEmpty(selectedRuntime)
    }

    private var selectedModelOrNil: String? {
        nilIfEmpty(selectedModel)
    }

    private func applySelectionDefaults(forceModelRefresh: Bool = false) {
        let preferredRuntime = preferredRuntimeForSelectedAgent()
        if selectedRuntime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            selectedRuntime = preferredRuntime ?? availableRuntimes.first?.id ?? "copilot"
        } else if !availableRuntimes.isEmpty, !availableRuntimes.contains(where: { $0.id == selectedRuntime }) {
            selectedRuntime = preferredRuntime ?? availableRuntimes.first?.id ?? selectedRuntime
        }

        let preferredModel = preferredModelForSelectedAgent(runtime: selectedRuntime)
        let availableModelIDs = Set(availableModels.map(\.id))
        let currentModelMissing = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!availableModelIDs.isEmpty && !availableModelIDs.contains(selectedModel))

        if forceModelRefresh || currentModelMissing {
            if let preferredModel, availableModelIDs.isEmpty || availableModelIDs.contains(preferredModel) {
                selectedModel = preferredModel
            } else if let firstModel = availableModels.first?.id {
                selectedModel = firstModel
            }
        }
    }

    private func preferredRuntimeForSelectedAgent() -> String? {
        agents.first(where: { $0.name == selectedAgent })?.primaryRuntime
    }

    private func preferredModelForSelectedAgent(runtime: String) -> String? {
        guard let agent = agents.first(where: { $0.name == selectedAgent }) else { return nil }
        guard let model = agent.primaryModel else { return nil }
        if let agentRuntime = agent.primaryRuntime, !agentRuntime.isEmpty, agentRuntime != runtime {
            return nil
        }
        return model
    }

    private func loadAvailableModels(for runtime: String) async {
        guard hasAuthToken else {
            availableModels = []
            applySelectionDefaults(forceModelRefresh: true)
            return
        }

        let trimmed = runtime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            availableModels = []
            return
        }

        do {
            availableModels = try await client.models(runtime: trimmed)
        } catch {
            availableModels = []
        }

        applySelectionDefaults(forceModelRefresh: true)
        saveConfiguration()
    }

    private func refreshSessionStatus(sessionID: String) async {
        do {
            let status = try await client.sessionStatus(sessionID: sessionID)
            if let agent = status.agent, !agent.isEmpty { selectedAgent = agent }
            if let runtime = status.runtime, !runtime.isEmpty { selectedRuntime = runtime }
            if let model = status.model, !model.isEmpty { selectedModel = model }
            saveConfiguration()
        } catch {}
    }

    private func applySessionPermissionModeIfNeeded(sessionID: String) async throws {
        guard selectedPermissionMode == "elevated" || selectedPermissionMode == "sandboxed" else { return }
        _ = try await client.execute(sessionID: sessionID, query: "/mode \(selectedPermissionMode)", agent: nil, runtime: nil, model: nil)
    }

    private func applyPendingSessionConfiguration(
        sessionID: String,
        desiredAgent: String,
        desiredRuntime: String?,
        desiredModel: String?
    ) async throws {
        let trimmedAgent = desiredAgent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedAgent.isEmpty, trimmedAgent != selectedAgent {
            _ = try await client.execute(sessionID: sessionID, query: "/agent set \(trimmedAgent)", agent: nil, runtime: nil, model: nil)
        }

        if let runtime = desiredRuntime?.trimmingCharacters(in: .whitespacesAndNewlines), !runtime.isEmpty {
            _ = try await client.execute(sessionID: sessionID, query: "/runtime set \(runtime)", agent: nil, runtime: nil, model: nil)
        }

        if let model = desiredModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            let escaped = model.replacingOccurrences(of: "\"", with: "\\\"")
            _ = try await client.execute(sessionID: sessionID, query: "/model set \"\(escaped)\"", agent: nil, runtime: nil, model: nil)
        }

        await refreshSessionStatus(sessionID: sessionID)
    }

    private func runSessionConfigurationCommand(
        command: String,
        afterSuccess: @escaping @MainActor () async -> Void = {}
    ) async {
        guard let sessionID = currentSessionID, hasAuthToken else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await client.execute(sessionID: sessionID, query: command, agent: nil, runtime: nil, model: nil)
            chatMessages.append(ChatMessage(role: .system, text: response.response))
            await afterSuccess()
            saveConfiguration()
            await loadHistorySessions()
        } catch {
            let message = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
        }
    }

    private var hasAuthToken: Bool {
        !configuration.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var optionalIdentity: String? {
        let identity = configuration.identity.trimmingCharacters(in: .whitespacesAndNewlines)
        return identity.isEmpty ? nil : identity
    }

    private func handleAuthErrorIfNeeded(_ error: Error) -> String? {
        guard case WeeAPIError.httpStatus(401, _) = error else { return nil }
        let message = "Session expired. Sign in with Telegram in Settings."
        configuration.token = ""
        currentSessionID = nil
        authPairingIdentity = nil
        authStatusMessage = message
        KeychainStore.saveToken("")
        return message
    }

    // MARK: - Stream Helpers

    private func streamPayload(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = trimmed
            .dropFirst("data:".count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        return String(payload)
    }

    private func streamActivityText(from event: StreamEvent) -> String {
        guard event.type == "tool_call" else { return "" }
        let trimmedName = event.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmedName?.isEmpty == false ? trimmedName! : "tool"

        switch event.event {
        case "detected":
            return "Running \(label)..."
        case "completed":
            if event.isError == true,
               let output = event.output?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return "\(label) failed: \(output)"
            }
            return "Ran \(label)."
        default:
            return "Running \(label)..."
        }
    }

    private func preferredFinalStreamText(accumulated: String, doneResponse: String?) -> String {
        let normalizedAccumulated = normalizeCodexStreamText(accumulated)
        if !normalizedAccumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return normalizedAccumulated
        }
        return normalizeCodexStreamText(doneResponse ?? "")
    }

    private func normalizeCodexStreamText(_ text: String) -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let isCodexTransport = looksLikeCodexTransportFrames(text)
        guard isCodexTransport else {
            return text
        }

        var output: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineText = String(line)
            let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard trimmed.hasPrefix("{") else {
                output.append(lineText)
                continue
            }
            guard let event = parseJSONDictionary(trimmed) else {
                if isCodexTransport == false {
                    output.append(lineText)
                }
                continue
            }

            if let agentText = agentMessageText(from: event), !agentText.isEmpty {
                output.append(agentText)
            } else if let responseText = responseText(from: event), !responseText.isEmpty {
                output.append(responseText)
            }
        }
        return output.joined(separator: "\n")
    }

    private func looksLikeCodexTransportFrames(_ text: String) -> Bool {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), let event = parseJSONDictionary(String(trimmed)) else {
                continue
            }
            if let type = event["type"] as? String,
               codexTransportEventTypes.contains(type) || agentMessageText(from: event) != nil || responseText(from: event) != nil {
                return true
            }
        }
        return false
    }

    private var codexTransportEventTypes: Set<String> {
        [
            "thread.started", "thread.completed", "turn.started", "turn.completed", "turn.failed",
            "item.started", "item.completed", "response.started", "response.completed"
        ]
    }

    private func agentMessageText(from event: [String: Any]) -> String? {
        if event["type"] as? String == "agent_message" {
            return event["text"] as? String
        }
        guard event["type"] as? String == "item.completed",
              let item = event["item"] as? [String: Any],
              item["type"] as? String == "agent_message" else {
            return nil
        }
        return item["text"] as? String
    }

    private func responseText(from event: [String: Any]) -> String? {
        if let text = event["text"] as? String {
            return text
        }
        if let delta = event["delta"] as? [String: Any],
           let text = (delta["text"] as? String) ?? (delta["content"] as? String) {
            return text
        }
        if let item = event["item"] as? [String: Any],
           let text = item["text"] as? String {
            return text
        }
        if let response = event["response"] as? [String: Any] {
            return responseText(from: response)
        }
        if let output = event["output"] as? [[String: Any]] {
            return output.compactMap { responseText(from: $0) }.joined(separator: "\n")
        }
        if let content = event["content"] as? [[String: Any]] {
            return content.compactMap { responseText(from: $0) }.joined(separator: "\n")
        }
        return nil
    }

    private func parseJSONDictionary(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Notifications

    private func notifyCompletedTasks(old: [BackgroundTaskSummary], new: [BackgroundTaskSummary]) {
        let oldStatuses = Dictionary(uniqueKeysWithValues: old.map { ($0.taskID, $0.status) })
        guard !oldStatuses.isEmpty else { return }

        for task in new {
            let prev = oldStatuses[task.taskID]
            guard let prev, prev == "running" || prev == "queued" else { continue }
            guard task.status == "completed" || task.status == "failed" else { continue }

            let content = UNMutableNotificationContent()
            if task.status == "completed" {
                content.title = "Task Completed"
                content.body = "\(task.agent): \(task.prompt)"
                content.sound = .default
            } else {
                content.title = "Task Failed"
                content.body = "\(task.agent): \(task.prompt)"
                content.sound = UNNotificationSound.defaultCritical
            }

            let request = UNNotificationRequest(
                identifier: "wee.task.\(task.taskID)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func scheduleDueNotifications(for cards: [KanbanCard]) async {
        let center = UNUserNotificationCenter.current()
        let oldIDs = defaults.stringArray(forKey: "wee.kanbanNotificationIDs") ?? []
        center.removePendingNotificationRequests(withIdentifiers: oldIDs)

        guard !cards.isEmpty else {
            defaults.set([], forKey: "wee.kanbanNotificationIDs")
            return
        }

        var identifiers: [String] = []
        for card in cards {
            let identifier = "wee.kanban.\(card.id)"
            let content = UNMutableNotificationContent()
            content.sound = .default

            switch card.dueBucket {
            case "overdue":
                content.title = "Overdue TODO"
                content.body = card.title
            case "today":
                content.title = "TODO Due Today"
                content.body = card.title
            case "soon":
                content.title = "TODO Due Soon"
                content.body = card.title
            default:
                continue
            }

            guard let triggerDate = parseDueDate(card.due) else { continue }
            let fireDate = triggerDate <= Date() ? Date().addingTimeInterval(5) : triggerDate
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
                identifiers.append(identifier)
            } catch {
                continue
            }
        }
        defaults.set(identifiers, forKey: "wee.kanbanNotificationIDs")
    }

    private func parseDueDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    private static var launchToken: String {
        let environment = ProcessInfo.processInfo.environment
        let token = (environment["WEE_API_TOKEN"] ?? environment["WEE_AUTH_TOKEN"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            return String(token.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return token
    }
}

import AppKit
import Foundation

struct APIConfiguration: Equatable {
    var baseURLString: String
    var token: String
    var identity: String
    var channel: String
    var allowInsecureTLS: Bool

    static let defaults = APIConfiguration(
        baseURLString: "https://100.124.186.75:8000",
        token: "",
        identity: "",
        channel: "telegram",
        allowInsecureTLS: true
    )
}

enum WeeEnvironment: String, CaseIterable, Identifiable, Codable {
    case local
    case remote

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String { self == .local ? "desktopcomputer" : "network" }
}

struct LocalAPIServiceConfiguration: Equatable, Codable {
    var executablePath: String
    var arguments: String
    var workingDirectory: String
    var autoStart: Bool
    var repositoryURL: String
    var checkoutDirectory: String

    static let defaults = LocalAPIServiceConfiguration(
        executablePath: "/opt/homebrew/bin/python3",
        arguments: "agent_manager.py --api",
        workingDirectory: "/opt/n8n-copilot-shim-dev",
        autoStart: false,
        repositoryURL: "https://github.com/leprachuan/Wee-Orchestrator.git",
        checkoutDirectory: "~/Developer/Wee-Orchestrator"
    )
}

struct LocalModelConfiguration: Equatable, Codable {
    var selectedModel: String
    var autoStartRunner: Bool

    static let defaults = LocalModelConfiguration(
        selectedModel: "",
        autoStartRunner: false
    )
}

struct OllamaModelSummary: Identifiable, Hashable {
    let name: String
    let sizeBytes: Int64?

    var id: String { name }

    var sizeLabel: String {
        guard let sizeBytes else { return "Downloaded" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct LocalModelCatalogItem: Identifiable, Hashable {
    let name: String
    let displayName: String
    let parameterSize: String
    let contextWindow: Int
    let estimatedDownloadGB: Double
    let description: String

    var id: String { name }

    static let recommended: [LocalModelCatalogItem] = [
        .init(name: "gemma4:e4b", displayName: "Gemma 4 E4B", parameterSize: "4B effective", contextWindow: 128_000, estimatedDownloadGB: 3.4, description: "Best fit for this Mac: efficient local reasoning with a 128K context window."),
        .init(name: "gemma4:12b", displayName: "Gemma 4 12B", parameterSize: "12B", contextWindow: 256_000, estimatedDownloadGB: 8.0, description: "Recommended quality step-up for local agents and multimodal work."),
        .init(name: "qwen3.6:27b", displayName: "Qwen 3.6 27B", parameterSize: "27B", contextWindow: 256_000, estimatedDownloadGB: 17.0, description: "Current agentic coding and reasoning model. Runs near this Mac’s memory limit."),
        .init(name: "gemma4:26b", displayName: "Gemma 4 26B", parameterSize: "26B MoE", contextWindow: 256_000, estimatedDownloadGB: 16.0, description: "High-quality workstation option; expect memory pressure with long prompts."),
        .init(name: "qwen3.6:35b", displayName: "Qwen 3.6 35B", parameterSize: "35B A3B", contextWindow: 256_000, estimatedDownloadGB: 24.0, description: "Not recommended on 24 GB unified memory; reserve for larger Macs."),
        .init(name: "gpt-oss:20b", displayName: "GPT-OSS 20B", parameterSize: "20B", contextWindow: 131_072, estimatedDownloadGB: 13.0, description: "Long-context local reasoning option for capable Apple Silicon Macs.")
    ]
}

struct BotTokenStatus: Decodable, Equatable {
    let agent: String
    let channel: String
    let configured: Bool
    let secretName: String?
    let allowedUsers: [String]

    enum CodingKeys: String, CodingKey {
        case agent, channel, configured
        case secretName = "secret_name"
        case allowedUsers = "allowed_users"
    }
}

struct BotTokenUpdateRequest: Encodable {
    let token: String
    let allowedUsers: [String]

    enum CodingKeys: String, CodingKey {
        case token
        case allowedUsers = "allowed_users"
    }
}

struct PairingRequest: Encodable {
    let identity: String
    let channel: String
}

struct PairingRequestResponse: Decodable, Equatable {
    let message: String
    let expiresIn: Int?
    let identityResolved: String?

    enum CodingKeys: String, CodingKey {
        case message
        case expiresIn = "expires_in"
        case identityResolved = "identity_resolved"
    }
}

struct PairingVerificationRequest: Encodable {
    let code: String
    let identity: String
}

struct PairingVerificationResponse: Decodable, Equatable {
    let token: String
    let expiresIn: Int?
    let absoluteExpiresIn: Int?
    let identity: String
    let channel: String
    let username: String?

    enum CodingKeys: String, CodingKey {
        case token
        case expiresIn = "expires_in"
        case absoluteExpiresIn = "absolute_expires_in"
        case identity
        case channel
        case username
    }
}

struct HealthResponse: Decodable, Equatable {
    let status: String
    let uptimeSeconds: Double?
    let version: String?
    let environment: String?
    let agentsLoaded: Int?
    let schedulerEnabled: Bool?
    let activeSessions: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case uptimeSeconds = "uptime_seconds"
        case version
        case environment
        case agentsLoaded = "agents_loaded"
        case schedulerEnabled = "scheduler_enabled"
        case activeSessions = "active_sessions"
    }
}

struct AppConfigResponse: Decodable, Equatable {
    let schedulerEnabled: Bool?
    let backgroundTasksEnabled: Bool?
    let appEnv: String?

    enum CodingKeys: String, CodingKey {
        case schedulerEnabled = "scheduler_enabled"
        case backgroundTasksEnabled = "background_tasks_enabled"
        case appEnv = "app_env"
    }
}

struct AgentsResponse: Decodable {
    let agents: [AgentSummary]
}

struct AgentsConfigResponse: Codable, Equatable {
    var agents: [AgentConfiguration]
}

struct AgentConfiguration: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var path: String
    var description: String?
    var primaryRuntime: String?
    var primaryModel: String?
    var fallbackRuntime: String?
    var fallbackModel: String?
    var maxConcurrent: Int?
    var permissions: AgentPermissions

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case description
        case runtime
        case model
        case primaryRuntime = "primary_runtime"
        case primaryModel = "primary_model"
        case fallbackRuntime = "fallback_runtime"
        case fallbackModel = "fallback_model"
        case maxConcurrent = "max_concurrent"
        case permissions
    }

    init(
        name: String = "new-agent",
        path: String = "/opt/",
        description: String? = nil,
        primaryRuntime: String? = nil,
        primaryModel: String? = nil,
        fallbackRuntime: String? = nil,
        fallbackModel: String? = nil,
        maxConcurrent: Int? = 1,
        permissions: AgentPermissions = .defaultRestricted
    ) {
        self.name = name
        self.path = path
        self.description = description
        self.primaryRuntime = primaryRuntime
        self.primaryModel = primaryModel
        self.fallbackRuntime = fallbackRuntime
        self.fallbackModel = fallbackModel
        self.maxConcurrent = maxConcurrent
        self.permissions = permissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "new-agent"
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? "/opt/"
        description = try container.decodeIfPresent(String.self, forKey: .description)
        primaryRuntime = try container.decodeIfPresent(String.self, forKey: .primaryRuntime)
            ?? container.decodeIfPresent(String.self, forKey: .runtime)
        primaryModel = try container.decodeIfPresent(String.self, forKey: .primaryModel)
            ?? container.decodeIfPresent(String.self, forKey: .model)
        fallbackRuntime = try container.decodeIfPresent(String.self, forKey: .fallbackRuntime)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        maxConcurrent = try container.decodeIfPresent(Int.self, forKey: .maxConcurrent)
        permissions = try container.decodeIfPresent(AgentPermissions.self, forKey: .permissions) ?? .defaultRestricted
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(description.nilIfBlank, forKey: .description)
        try container.encodeIfPresent(primaryRuntime.nilIfBlank, forKey: .primaryRuntime)
        try container.encodeIfPresent(primaryModel.nilIfBlank, forKey: .primaryModel)
        try container.encodeIfPresent(fallbackRuntime.nilIfBlank, forKey: .fallbackRuntime)
        try container.encodeIfPresent(fallbackModel.nilIfBlank, forKey: .fallbackModel)
        try container.encodeIfPresent(maxConcurrent, forKey: .maxConcurrent)
        try container.encode(permissions, forKey: .permissions)
    }
}

struct AgentPermissions: Codable, Equatable {
    var mode: String
    var directories: DirectoryPermissions
    var tools: ToolsPermissions
    var network: NetworkPermissions
    var mcp: MCPPermissions

    static let defaultRestricted = AgentPermissions(
        mode: "restricted",
        directories: DirectoryPermissions(),
        tools: ToolsPermissions(allow: ["*"], deny: []),
        network: NetworkPermissions(allowURLs: ["*"], denyURLs: []),
        mcp: MCPPermissions(allow: [], deny: ["*"])
    )
}

struct DirectoryPermissions: Codable, Equatable {
    var allowRead: [String] = []
    var allowWrite: [String] = []
    var deny: [String] = []

    enum CodingKeys: String, CodingKey {
        case allowRead = "allow_read"
        case allowWrite = "allow_write"
        case deny
    }
}

struct ToolsPermissions: Codable, Equatable {
    var allow: [String] = []
    var deny: [String] = []
}

struct NetworkPermissions: Codable, Equatable {
    var allowURLs: [String] = []
    var denyURLs: [String] = []

    enum CodingKeys: String, CodingKey {
        case allowURLs = "allow_urls"
        case denyURLs = "deny_urls"
    }
}

struct MCPPermissions: Codable, Equatable {
    var allow: [String] = []
    var deny: [String] = []
}

struct EmptyAPIResponse: Decodable {}

struct CancelSessionResponse: Decodable {
    let cancelled: Bool
    let message: String
}

struct KanbanSettingsResponse: Decodable, Equatable {
    let githubRepo: String
    let effectiveRepo: String
    let fallbackRepo: String

    enum CodingKeys: String, CodingKey {
        case githubRepo = "github_repo"
        case effectiveRepo = "effective_repo"
        case fallbackRepo = "fallback_repo"
    }
}

struct KanbanSettingsUpdateRequest: Encodable {
    let githubRepo: String

    enum CodingKeys: String, CodingKey {
        case githubRepo = "github_repo"
    }
}

struct EnvSettingsResponse: Decodable, Equatable {
    let content: String?
    let exists: Bool?
}

struct EnvSettingsUpdateRequest: Encodable {
    let content: String
}

struct RestartServicesResponse: Decodable, Equatable {
    let results: [String: String]?
    let message: String?
}

struct NotificationSettingsResponse: Codable, Equatable {
    var notificationsEnabled: Bool
    let updatedAt: String?
    let available: Bool?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case notificationsEnabled = "notifications_enabled"
        case updatedAt = "updated_at"
        case available
        case message
    }
}

struct RuntimeEntry: Decodable, Identifiable, Hashable {
    let id: String
    let label: String?
    let icon: String?

    init(id: String, label: String? = nil, icon: String? = nil) {
        self.id = id
        self.label = label
        self.icon = icon
    }

    var displayLabel: String {
        let prefix = icon.map { "\($0) " } ?? ""
        return prefix + (label ?? id)
    }
}

struct RuntimesResponse: Decodable {
    let runtimes: [RuntimeRaw]

    enum RuntimeRaw: Decodable {
        case string(String)
        case object(RuntimeEntry)

        init(from decoder: Decoder) throws {
            if let str = try? decoder.singleValueContainer().decode(String.self) {
                self = .string(str)
            } else {
                self = .object(try RuntimeEntry(from: decoder))
            }
        }

        var entry: RuntimeEntry {
            switch self {
            case .string(let s): RuntimeEntry(id: s)
            case .object(let e): e
            }
        }
    }

    var entries: [RuntimeEntry] {
        runtimes.map(\.entry)
    }
}

struct ModelCatalogResponse: Decodable {
    let runtime: String
    let models: [ModelCatalogEntry]
    let error: String?
}

struct ModelCatalogEntry: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let group: String?
}

struct AgentSummary: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    let path: String?
    let primaryRuntime: String?
    let primaryModel: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case primaryRuntime = "primary_runtime"
        case primaryModel = "primary_model"
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

struct BackgroundTasksResponse: Decodable {
    let tasks: [BackgroundTaskSummary]
}

struct ScheduledJobsResponse: Decodable {
    let success: Bool?
    let result: [ScheduledJobSummary]
    let message: String?
}

struct ScheduledJobMutationRequest: Encodable {
    let name: String
    let schedule: String
    let agent: String?
    let runtime: String?
    let model: String?
    let fallbackRuntime: String?
    let fallbackModel: String?
    let mode: String
    let task: String
    let notify: Bool
    let recurring: Bool
    let timeout: Int
    let permissionMode: String?
    let workingDir: String?

    enum CodingKeys: String, CodingKey {
        case name, schedule, agent, runtime, model, mode, task, notify, recurring, timeout
        case fallbackRuntime = "fallback_runtime"
        case fallbackModel = "fallback_model"
        case permissionMode = "permission_mode"
        case workingDir = "working_dir"
    }
}

struct ScheduleValidationRequest: Encodable {
    let schedule: String
}

struct ScheduleValidationResponse: Decodable {
    let success: Bool?
    let cron: String?
    let humanReadable: String?
    let nextRun: String?
    let method: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, cron, method, message
        case humanReadable = "human_readable"
        case nextRun = "next_run"
    }
}

struct ScheduledJobResultsResponse: Decodable {
    let success: Bool?
    let result: [ScheduledExecutionResult]
    let message: String?
}

struct ScheduledExecutionResult: Decodable, Identifiable, Hashable {
    var id: String { "\(timestamp ?? "unknown"):\(success):\(output?.hashValue ?? error?.hashValue ?? 0)" }

    let success: Bool
    let timestamp: String?
    let output: String?
    let error: String?
    let durationSeconds: Double?
    let runtime: String?
    let model: String?
    let taskID: String?

    enum CodingKeys: String, CodingKey {
        case success, timestamp, output, error, runtime, model
        case durationSeconds = "duration_seconds"
        case taskID = "task_id"
    }
}

struct ScheduledJobSummary: Decodable, Identifiable, Hashable {
    var id: String { jobID }

    let jobID: String
    let name: String?
    let agent: String?
    let runtime: String?
    let model: String?
    let mode: String?
    let permissionMode: String?
    let task: String?
    let schedule: String?
    let cron: String?
    let workingDir: String?
    let notify: Bool?
    let fallbackRuntime: String?
    let fallbackModel: String?
    let recurring: Bool?
    let createdAt: String?
    let nextRun: String?
    let lastRun: String?
    let enabled: Bool?
    let retries: Int?
    let timeout: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case agent
        case runtime
        case model
        case mode
        case permissionMode = "permission_mode"
        case task
        case schedule
        case cron
        case workingDir = "working_dir"
        case notify
        case fallbackRuntime = "fallback_runtime"
        case fallbackModel = "fallback_model"
        case recurring
        case createdAt = "created_at"
        case nextRun = "next_run"
        case lastRun = "last_run"
        case enabled
        case retries
        case timeout
    }

    init(
        id: String,
        name: String?,
        agent: String?,
        runtime: String?,
        model: String?,
        mode: String?,
        permissionMode: String?,
        task: String?,
        schedule: String?,
        cron: String?,
        workingDir: String?,
        notify: Bool?,
        fallbackRuntime: String?,
        fallbackModel: String?,
        recurring: Bool?,
        createdAt: String?,
        nextRun: String?,
        lastRun: String?,
        enabled: Bool?,
        retries: Int?,
        timeout: Int?
    ) {
        self.jobID = id
        self.name = name
        self.agent = agent
        self.runtime = runtime
        self.model = model
        self.mode = mode
        self.permissionMode = permissionMode
        self.task = task
        self.schedule = schedule
        self.cron = cron
        self.workingDir = workingDir
        self.notify = notify
        self.fallbackRuntime = fallbackRuntime
        self.fallbackModel = fallbackModel
        self.recurring = recurring
        self.createdAt = createdAt
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.enabled = enabled
        self.retries = retries
        self.timeout = timeout
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(String.self, forKey: .id)
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name)
        jobID = decodedID ?? decodedName ?? UUID().uuidString
        name = decodedName
        agent = try container.decodeIfPresent(String.self, forKey: .agent)
        runtime = try container.decodeIfPresent(String.self, forKey: .runtime)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        permissionMode = try container.decodeIfPresent(String.self, forKey: .permissionMode)
        task = try container.decodeIfPresent(String.self, forKey: .task)
        schedule = try container.decodeIfPresent(String.self, forKey: .schedule)
        cron = try container.decodeIfPresent(String.self, forKey: .cron)
        workingDir = try container.decodeIfPresent(String.self, forKey: .workingDir)
        notify = try container.decodeIfPresent(Bool.self, forKey: .notify)
        fallbackRuntime = try container.decodeIfPresent(String.self, forKey: .fallbackRuntime)
        fallbackModel = try container.decodeIfPresent(String.self, forKey: .fallbackModel)
        recurring = try container.decodeIfPresent(Bool.self, forKey: .recurring)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        nextRun = try container.decodeIfPresent(String.self, forKey: .nextRun)
        lastRun = try container.decodeIfPresent(String.self, forKey: .lastRun)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled)
        retries = try container.decodeIfPresent(Int.self, forKey: .retries)
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout)
    }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? jobID : trimmed
    }

    var displaySchedule: String {
        let trimmed = (schedule ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No schedule" : trimmed
    }
}

struct KanbanBoardResponse: Decodable, Equatable {
    let success: Bool
    let columns: [String: [KanbanCard]]
    let agents: [String]
    let sources: [String]
    let total: Int
    let repo: String?

    var dueCards: [KanbanCard] {
        KanbanColumnID.allCases
            .filter { $0 != .done }
            .flatMap { columns[$0.rawValue] ?? [] }
            .filter { ["overdue", "today", "soon"].contains($0.dueBucket) }
    }
}

struct LegacyTodosResponse: Decodable, Equatable {
    let todos: [LegacyTodo]
    let count: Int?
    let agent: String?
    let file: String?
}

struct LegacyTodo: Decodable, Equatable {
    let description: String
    let due: String?
    let labels: [String]?
    let notes: [String]?
    let details: String?
}

struct KanbanCard: Decodable, Identifiable, Hashable, Equatable {
    let id: String
    let title: String
    let source: String
    let status: String
    let agent: String?
    let priority: String
    let urgency: String
    let due: String?
    let dueBucket: String
    let isOverdue: Bool
    let labels: [String]
    let details: String
    let url: String?
    let createdAt: String?
    let updatedAt: String?
    let githubIssueNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case status
        case agent
        case priority
        case urgency
        case due
        case dueBucket = "due_bucket"
        case isOverdue = "is_overdue"
        case labels
        case details
        case url
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case githubIssueNumber = "github_issue_number"
    }
}

struct KanbanComment: Decodable, Identifiable, Hashable, Equatable {
    let id: String
    let body: String
    let createdAt: String?
    let author: KanbanCommentAuthor?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case createdAt = "createdAt"
        case author
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        author = try container.decodeIfPresent(KanbanCommentAuthor.self, forKey: .author)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? "\(createdAt ?? ""):\(body.hashValue)"
    }
}

struct KanbanCommentAuthor: Decodable, Hashable, Equatable {
    let login: String?
}

struct KanbanItemDetail: Decodable, Identifiable, Hashable, Equatable {
    let id: String
    let title: String
    let source: String
    let status: String
    let agent: String?
    let priority: String
    let urgency: String
    let due: String?
    let dueBucket: String
    let isOverdue: Bool
    let labels: [String]
    let details: String
    let url: String?
    let createdAt: String?
    let updatedAt: String?
    let githubIssueNumber: Int?
    let comments: [KanbanComment]
    let repo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case source
        case status
        case agent
        case priority
        case urgency
        case due
        case dueBucket = "due_bucket"
        case isOverdue = "is_overdue"
        case labels
        case details
        case url
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case githubIssueNumber = "github_issue_number"
        case comments
        case repo
    }
}

struct KanbanItemUpdateRequest: Encodable {
    let title: String?
    let details: String?
    let status: String?
    let agent: String?
    let due: String?
    let priority: String?
    let urgency: String?
    let labels: [String]?
}

struct KanbanCommentRequest: Encodable {
    let body: String
}

struct KanbanDispatchRequest: Encodable {
    let agent: String
    let prompt: String?
    let timeout: Int?
}

struct KanbanDispatchResponse: Decodable {
    let success: Bool
    let task: CreateBackgroundTaskResponse
    let item: KanbanItemDetail
}

extension KanbanBoardResponse {
    static func legacyTodos(_ response: LegacyTodosResponse) -> KanbanBoardResponse {
        let cards = response.todos.enumerated().map { index, todo in
            let labels = todo.labels ?? []
            let status = labels.labelValue(prefix: "status:") ?? "todo"
            let normalizedStatus = KanbanColumnID(rawValue: status)?.rawValue ?? "todo"
            let dueBucket = Self.dueBucket(for: todo.due)
            return KanbanCard(
                id: "legacy-todo:\(index):\(todo.description)",
                title: todo.description,
                source: "todo",
                status: normalizedStatus,
                agent: labels.labelValue(prefix: "agent:") ?? response.agent,
                priority: labels.labelValue(prefix: "priority:") ?? "normal",
                urgency: labels.contains(where: { ["urgent", "urgency:urgent", "urgency:high"].contains($0.lowercased()) }) ? "urgent" : "normal",
                due: todo.due,
                dueBucket: dueBucket,
                isOverdue: dueBucket == "overdue",
                labels: labels,
                details: todo.details ?? "",
                url: nil,
                createdAt: nil,
                updatedAt: nil,
                githubIssueNumber: nil
            )
        }

        let columns = Dictionary(grouping: cards, by: \.status)
        return KanbanBoardResponse(
            success: true,
            columns: KanbanColumnID.allCases.reduce(into: [:]) { result, column in
                result[column.rawValue] = columns[column.rawValue] ?? []
            },
            agents: Array(Set(cards.compactMap(\.agent))).sorted(),
            sources: cards.isEmpty ? [] : ["todo"],
            total: cards.count,
            repo: nil
        )
    }

    private static func dueBucket(for due: String?) -> String {
        guard let date = due.flatMap(parseLegacyDate) else { return "none" }
        let calendar = Calendar.current
        let now = Date()

        if date < now { return "overdue" }
        if calendar.isDate(date, inSameDayAs: now) { return "today" }
        if let soon = calendar.date(byAdding: .day, value: 3, to: now), date <= soon {
            return "soon"
        }
        return "future"
    }

    private static func parseLegacyDate(_ value: String) -> Date? {
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
}

private extension Array where Element == String {
    func labelValue(prefix: String) -> String? {
        first { $0.lowercased().hasPrefix(prefix) }?
            .split(separator: ":", maxSplits: 1)
            .last
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

enum KanbanColumnID: String, CaseIterable, Identifiable {
    case todo
    case inProgress = "in-progress"
    case aiActive = "ai-active"
    case pendingReview = "pending-review"
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .aiActive: "AI Active"
        case .pendingReview: "Review"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .todo: "tray"
        case .inProgress: "arrow.triangle.2.circlepath"
        case .aiActive: "sparkles"
        case .pendingReview: "checklist"
        case .done: "checkmark.circle"
        }
    }
}

struct BackgroundTaskSummary: Decodable, Identifiable, Hashable {
    var id: String { taskID }
    let taskID: String
    let agent: String
    let runtime: String?
    let model: String?
    let prompt: String
    let status: String
    let createdAt: String?
    let completedAt: String?
    let error: String?
    let usedFallback: Bool?
    let actualRuntime: String?
    let actualModel: String?

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case agent
        case runtime
        case model
        case prompt
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case error
        case usedFallback = "used_fallback"
        case actualRuntime = "actual_runtime"
        case actualModel = "actual_model"
    }
}

enum BackgroundTaskOrdering {
    /// Keep task history useful at a glance. The API does not guarantee an
    /// ordering, so order presentation by creation time and leave entries with
    /// unparseable timestamps in their original relative order.
    static func newestFirst(_ tasks: [BackgroundTaskSummary]) -> [BackgroundTaskSummary] {
        tasks.enumerated()
            .sorted { lhs, rhs in
                let lhsDate = date(from: lhs.element.createdAt)
                let rhsDate = date(from: rhs.element.createdAt)
                switch (lhsDate, rhsDate) {
                case let (left?, right?):
                    return left == right ? lhs.offset < rhs.offset : left > right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    static func date(from value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct BackgroundTaskDetail: Decodable, Identifiable {
    var id: String { taskID }
    let taskID: String
    let sessionID: String?
    let agent: String
    let runtime: String?
    let model: String?
    let prompt: String
    let status: String
    let pid: Int?
    let createdAt: String?
    let completedAt: String?
    let recentOutput: [String]?
    let error: String?
    let toolCallCount: Int?
    let usedFallback: Bool?
    let actualRuntime: String?
    let actualModel: String?
    let fallbackRuntime: String?
    let fallbackModel: String?

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case sessionID = "session_id"
        case agent
        case runtime
        case model
        case prompt
        case status
        case pid
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case recentOutput = "recent_output"
        case error
        case toolCallCount = "tool_call_count"
        case usedFallback = "used_fallback"
        case actualRuntime = "actual_runtime"
        case actualModel = "actual_model"
        case fallbackRuntime = "fallback_runtime"
        case fallbackModel = "fallback_model"
    }
}

/// Powers a bounded live-log poll while the task detail modal is open.
struct BackgroundTaskLogs: Decodable {
    let status: String
    let outputLines: [String]
    let truncated: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case status
        case outputLines = "output_lines"
        case truncated
        case error
    }
}

struct CreateBackgroundTaskRequest: Encodable {
    let prompt: String
    let agent: String?
    let runtime: String?
    let model: String?
    let timeout: Int?
    let notify: Bool?
    let permissionMode: String?

    enum CodingKeys: String, CodingKey {
        case prompt
        case agent
        case runtime
        case model
        case timeout
        case notify
        case permissionMode = "permission_mode"
    }
}

struct CreateBackgroundTaskResponse: Decodable {
    let taskID: String
    let sessionID: String?
    let agent: String
    let runtime: String?
    let model: String?
    let permissionMode: String?
    let status: String
    let queuePosition: Int?
    let timeout: Int?

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case sessionID = "session_id"
        case agent
        case runtime
        case model
        case permissionMode = "permission_mode"
        case status
        case queuePosition = "queue_position"
        case timeout
    }
}

struct CreateSessionRequest: Encodable {
    let sessionID: String?
    let agent: String?
    let model: String?
    let runtime: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agent
        case model
        case runtime
    }
}

struct CreateSessionResponse: Decodable {
    let sessionID: String
    let agent: String?
    let model: String?
    let runtime: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agent
        case model
        case runtime
    }
}

struct ExecuteRequest: Encodable {
    let query: String
    let timeout: Int?
    let model: String?
    let runtime: String?
    let agent: String?
}

struct StreamRequest: Encodable {
    let query: String
    let model: String?
    let runtime: String?
    let agent: String?
}

struct ExecuteResponse: Decodable {
    let sessionID: String
    let response: String
    let runtime: String?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case response
        case runtime
        case model
    }
}

struct SessionStatusResponse: Decodable {
    let sessionID: String
    let agent: String?
    let runtime: String?
    let model: String?
    let contextUsage: SessionContextUsage?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case agent
        case runtime
        case model
        case contextUsage = "context_usage"
    }
}

struct SessionContextUsage: Decodable, Equatable {
    let runtime: String?
    let model: String?
    let contextWindow: Int
    let currentContextTokens: Int
    let percentUsed: Double?
    let compactionTriggerTokens: Int?

    enum CodingKeys: String, CodingKey {
        case runtime, model
        case contextWindow = "context_window"
        case currentContextTokens = "current_context_tokens"
        case percentUsed = "percent_used"
        case compactionTriggerTokens = "compaction_trigger_tokens"
    }

    var progress: Double {
        min(1, max(0, percentUsed.map { $0 / 100 } ?? Double(currentContextTokens) / Double(max(contextWindow, 1))))
    }
}

struct HistorySessionsResponse: Decodable {
    let sessions: [HistorySessionSummary]
}

struct HistorySessionSummary: Decodable, Identifiable, Hashable {
    var id: String { sessionID }

    let sessionID: String
    let title: String?
    let preview: String?
    let agent: String?
    let createdAt: Double?
    let updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case title
        case preview
        case agent
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        let trimmed = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Session \(sessionID)" : trimmed
    }

    var displayPreview: String {
        let trimmed = (preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No messages yet" : trimmed
    }
}

struct HistoryMessagesResponse: Decodable {
    let sessionID: String
    let messages: [HistoryMessage]
    let total: Int?
    let offset: Int?
    let limit: Int?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case messages
        case total
        case offset
        case limit
    }
}

struct HistoryMessage: Decodable, Hashable {
    let role: String
    let content: String
    let timestamp: Double?
}

struct ChatAttachment: Identifiable, Hashable {
    let id = UUID()
    let filename: String
    let data: Data
    let mimeType: String

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var nsImage: NSImage? {
        NSImage(data: data)
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role: String {
        case user
        case assistant
        case system
    }

    let id = UUID()
    let role: Role
    var text: String
    let attachments: [ChatAttachment]
    let createdAt = Date()
    /// True when this message marks a point where the backend reset the
    /// session's conversation context (see `SessionResetDetector`) — the
    /// assistant can no longer see anything before this message.
    var isContextBoundary: Bool = false

    init(role: Role, text: String, attachments: [ChatAttachment] = [], isContextBoundary: Bool = false) {
        self.role = role
        self.text = text
        self.attachments = attachments
        self.isContextBoundary = isContextBoundary
    }

    init(historyMessage: HistoryMessage) {
        role = Role(rawValue: historyMessage.role) ?? .system
        text = historyMessage.content
        attachments = []
        isContextBoundary = SessionResetDetector.indicatesReset(historyMessage.content)
    }
}

struct UploadResponse: Decodable {
    let success: Bool?
    let filename: String?
    let url: String?
    let uploadId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case success, filename, url, message
        case uploadId = "upload_id"
    }
}

struct TranscriptionResponse: Decodable {
    let text: String?
    let backend: String?
    let size: Int?
}

struct TextToSpeechRequest: Encodable {
    let text: String
    let voice: String?
}

struct StreamEvent: Decodable {
    let type: String
    let event: String?
    let text: String?
    let response: String?
    let message: String?
    let runtime: String?
    let model: String?
    let agent: String?
    let name: String?
    let input: String?
    let output: String?
    let status: String?
    let result: String?
    let isError: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case event
        case text
        case response
        case message
        case runtime
        case model
        case agent
        case name
        case input
        case output
        case status
        case result
        case isError = "is_error"
    }
}

struct BrowserRegistrationRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey { case clientID = "client_id" }
}

struct BrowserRegistrationResponse: Decodable {
    let registered: Bool
    let sessionID: String

    enum CodingKeys: String, CodingKey {
        case registered
        case sessionID = "session_id"
    }
}

struct BrowserCommandEnvelope: Decodable {
    let command: BrowserCommand?
}

struct BrowserCommand: Decodable, Identifiable {
    let id: String
    let action: String
    let url: String?
    let selector: String?
    let text: String?
    let script: String?
    let submit: Bool?
}

struct BrowserCommandResultRequest: Encodable {
    let clientID: String
    let commandID: String
    let result: String?
    let error: String?
    let url: String?
    let title: String?

    enum CodingKeys: String, CodingKey {
        case result, error, url, title
        case clientID = "client_id"
        case commandID = "command_id"
    }
}

struct BrowserResultAcceptedResponse: Decodable {
    let accepted: Bool
}

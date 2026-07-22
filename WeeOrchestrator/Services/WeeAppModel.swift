import AppKit
import Foundation
import Observation
import Security
import SwiftUI
import UserNotifications
import CryptoKit

private final class GitOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct OllamaTagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
        let name: String
        let size: Int64?
    }
}

/// Chat UI state is normally backed by one visible transcript. A stream can
/// continue while that transcript is no longer visible, however, so retain a
/// copy by environment and session until the API history has caught up.
struct ChatTranscriptKey: Hashable {
    let environment: String
    let sessionID: String

    init(environment: WeeEnvironment, sessionID: String) {
        self.environment = environment.rawValue
        self.sessionID = sessionID
    }

    var environmentValue: WeeEnvironment {
        WeeEnvironment(rawValue: environment) ?? .remote
    }
}

struct QueuedChatMessage: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let attachments: [ChatAttachment]
    let enqueuedAt = Date()
}

enum ChatComposerAction: Equatable {
    case send
    case cancel

    static func action(for prompt: String, attachments: [ChatAttachment]) -> ChatComposerAction {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines) == "/cancel" && attachments.isEmpty ? .cancel : .send
    }
}

struct ChatMessageQueueStore {
    private var queues: [ChatTranscriptKey: [QueuedChatMessage]] = [:]

    mutating func enqueue(_ message: QueuedChatMessage, for key: ChatTranscriptKey) {
        queues[key, default: []].append(message)
    }

    mutating func takeNext(for key: ChatTranscriptKey) -> QueuedChatMessage? {
        guard var queue = queues[key], !queue.isEmpty else { return nil }
        let next = queue.removeFirst()
        queues[key] = queue.isEmpty ? nil : queue
        return next
    }

    mutating func remove(id: UUID, for key: ChatTranscriptKey) -> QueuedChatMessage? {
        guard var queue = queues[key], let index = queue.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = queue.remove(at: index)
        queues[key] = queue.isEmpty ? nil : queue
        return removed
    }

    func messages(for key: ChatTranscriptKey) -> [QueuedChatMessage] {
        queues[key] ?? []
    }
}

struct ChatStreamTranscriptStore {
    static let maximumMessages = 50

    private var transcripts: [ChatTranscriptKey: [ChatMessage]] = [:]
    private var activeStreams: Set<ChatTranscriptKey> = []

    mutating func beginStream(for key: ChatTranscriptKey, messages: [ChatMessage]) {
        transcripts[key] = bounded(messages)
        activeStreams.insert(key)
    }

    mutating func retainTranscript(for key: ChatTranscriptKey, messages: [ChatMessage]) {
        transcripts[key] = bounded(messages)
    }

    mutating func updateMessage(id: UUID, for key: ChatTranscriptKey, update: (inout ChatMessage) -> Void) {
        guard var messages = transcripts[key],
              let index = messages.firstIndex(where: { $0.id == id }) else { return }
        update(&messages[index])
        transcripts[key] = bounded(messages)
    }

    mutating func finishStream(for key: ChatTranscriptKey) {
        activeStreams.remove(key)
    }

    func isStreaming(_ key: ChatTranscriptKey) -> Bool {
        activeStreams.contains(key)
    }

    func messages(for key: ChatTranscriptKey, serverMessages: [ChatMessage]) -> [ChatMessage] {
        guard let cached = transcripts[key] else { return bounded(serverMessages) }
        // While streaming, server history can legitimately lag behind the
        // current assistant response. Keep the local transcript authoritative
        // until the stream completes and the server has caught up.
        if activeStreams.contains(key) || serverMessages.count < cached.count {
            return cached
        }
        return bounded(serverMessages)
    }

    private func bounded(_ messages: [ChatMessage]) -> [ChatMessage] {
        Array(messages.suffix(Self.maximumMessages))
    }
}

struct AppSemanticVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let values = value.split(separator: ".", omittingEmptySubsequences: false)
        guard values.count == 3,
              let major = Int(values[0]),
              let minor = Int(values[1]),
              let patch = Int(values[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: AppSemanticVersion, rhs: AppSemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, draft, prerelease, assets
    }
}

struct MacAppUpdate: Identifiable, Equatable {
    let version: AppSemanticVersion
    let releaseNotes: String
    let archiveURL: URL
    let checksumURL: URL?
    let bodyChecksum: String?

    var id: String { version.description }
}

enum MacAppReleaseSelector {
    static func latestUpdate(from releases: [GitHubRelease], newerThan currentVersion: AppSemanticVersion) -> MacAppUpdate? {
        releases.compactMap { release -> MacAppUpdate? in
            guard !release.draft, !release.prerelease,
                  release.tagName.hasPrefix("macos-v"),
                  let version = AppSemanticVersion(String(release.tagName.dropFirst("macos-v".count))),
                  version > currentVersion else { return nil }

            let archiveName = "WeeOrchestrator-macOS-v\(version).zip"
            guard let archiveURL = release.assets.first(where: { $0.name == archiveName })?.browserDownloadURL else { return nil }
            let checksumURL = release.assets.first(where: { $0.name == "\(archiveName).sha256" })?.browserDownloadURL
            return MacAppUpdate(
                version: version,
                releaseNotes: release.body ?? "",
                archiveURL: archiveURL,
                checksumURL: checksumURL,
                bodyChecksum: checksum(in: release.body)
            )
        }
        .max(by: { $0.version < $1.version })
    }

    private static func checksum(in releaseNotes: String?) -> String? {
        guard let releaseNotes else { return nil }
        let pattern = #"SHA-256:\s*`?([A-Fa-f0-9]{64})`?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: releaseNotes, range: NSRange(releaseNotes.startIndex..., in: releaseNotes)),
              let range = Range(match.range(at: 1), in: releaseNotes) else { return nil }
        return String(releaseNotes[range]).lowercased()
    }
}

@MainActor
@Observable
final class WeeAppModel {
    private static let localSharedKeyAccount = "local-api-shared-key"
    private static let localOpenRouterKeyAccount = "local-openrouter-api-key"
    private static let appTextSizeKey = "wee.appTextSize"
    /// Issue #17: exposes a bounded, non-accessibility subset of
    /// DynamicTypeSize as simple "smaller/larger" steps rather than the full
    /// 12-step range, which is more control than a compact utility app needs.
    static let textSizeSteps: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge]
    private static let defaultTextSizeIndex = 3

    var activeEnvironment: WeeEnvironment
    var localConfiguration: APIConfiguration
    var remoteConfiguration: APIConfiguration
    var localServiceConfiguration: LocalAPIServiceConfiguration
    var localModelConfiguration: LocalModelConfiguration
    /// Kept in Keychain only. This value is supplied to the child local API
    /// process as OPENROUTER_API_KEY and is never saved in UserDefaults.
    var localOpenRouterAPIKey: String
    var ollamaModels: [OllamaModelSummary] = []
    var ollamaStatus = "Not checked"
    var isOllamaWorking = false
    /// Curated recommendations, seeded from `LocalModelCatalogItem.recommended` and refreshed
    /// with live Ollama registry data (context window, size) for the Qwen 3.6 / Gemma 4
    /// families when the registry is reachable. Falls back to the static seed otherwise.
    var curatedModels: [LocalModelCatalogItem] = LocalModelCatalogItem.recommended
    var registrySearchResults: [OllamaRegistryModel] = []
    var isSearchingRegistry = false
    var registrySearchStatus = ""
    @ObservationIgnored private var knownModelContextWindows: [String: Int] = [:]
    var localAgents: [AgentSummary] = []
    var remoteAgents: [AgentSummary] = []
    var isLocalServiceRunning = false
    var localServiceStatus = "Stopped"
    var weeCLIInstallationStatus = "Will install when Wee opens"
    var localServiceLog = ""
    var isLocalSourceWorking = false
    var localSourceStatus = "Not installed"
    var localSourceOutput = ""
    var localModelManifestStatus = ""
    var localModelManifestRuntimes: [String] = []
    var localKanbanRepository = ""
    var localKanbanEffectiveRepository = ""
    var localKanbanFallbackRepository = ""
    var localKanbanSettingsStatus = ""
    var isSavingLocalKanbanSettings = false
    var kanbanEnabled = true
    var appTextSize: DynamicTypeSize = WeeAppModel.textSizeSteps[WeeAppModel.defaultTextSizeIndex]
    var remoteSSHHost = ""
    var remoteSSHKeyPath = ""
    var remoteSSHRepositoryURL = "https://github.com/leprachuan/Wee-Orchestrator.git"
    var remoteSSHCheckoutDirectory = "/opt/n8n-copilot-shim-dev"
    var remoteSSHStatus = ""
    var remoteSSHOutput = ""
    var isRemoteSSHWorking = false
    var userAvatarImagePath = ""
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
    var chatHistoryTotal = 0
    var chatMessages: [ChatMessage] = [
        ChatMessage(role: .system, text: "Wee macOS client ready.")
    ]
    var selectedAgent: String = "orchestrator"
    var selectedRuntime: String = ""
    var selectedModel: String = ""
    var selectedPermissionMode: String = "restricted"
    var currentSessionID: String?
    var sessionContextUsage: SessionContextUsage?
    var isLoading = false
    var errorMessage: String?
    var lastRefresh: Date?
    var authPairingIdentity: String?
    var authStatusMessage: String?
    var availableAppUpdate: MacAppUpdate?
    var appUpdateStatus: String?
    var isCheckingForAppUpdate = false
    var isInstallingAppUpdate = false

    private let defaults = UserDefaults.standard
    private var previousTaskStatuses: [String: String] = [:]
    @ObservationIgnored var hourlyUpdateCheckTask: Task<Void, Never>?
    /// Test seam: counts actual loop starts (not calls suppressed by the
    /// already-running guard) so duplicate-loop prevention is verifiable
    /// without waiting out a real 3600s sleep.
    @ObservationIgnored private(set) var hourlyUpdateCheckLoopStartCount = 0
    @ObservationIgnored var backgroundTaskAutoRefreshTask: Task<Void, Never>?
    @ObservationIgnored private(set) var backgroundTaskAutoRefreshLoopStartCount = 0
    @ObservationIgnored private var localAPIProcess: Process?
    @ObservationIgnored private var localLogPipe: Pipe?
    @ObservationIgnored private var ollamaProcess: Process?
    @ObservationIgnored private var streamTranscripts = ChatStreamTranscriptStore()
    @ObservationIgnored private var queuedChatMessages = ChatMessageQueueStore()
    @ObservationIgnored private var queueDispatchingKeys: Set<ChatTranscriptKey> = []
    @ObservationIgnored private var cancellationRequestedKeys: Set<ChatTranscriptKey> = []
    /// The queue store is intentionally not observed directly. Bump this on
    /// every mutation so SwiftUI refreshes the visible per-session queue.
    private var chatQueueRevision = 0
    var isChatQueuePaused = false
    /// `streamTranscripts` is `@ObservationIgnored`. Bump this whenever a
    /// stream starts or stops so views showing another session's streaming
    /// state (e.g. the recent chats rail) refresh even when that session
    /// isn't the one currently visible.
    private var streamingRevision = 0

    var configuration: APIConfiguration {
        get { activeEnvironment == .local ? localConfiguration : remoteConfiguration }
        set {
            if activeEnvironment == .local { localConfiguration = newValue }
            else { remoteConfiguration = newValue }
        }
    }

    init() {
        activeEnvironment = WeeEnvironment(rawValue: defaults.string(forKey: "wee.activeEnvironment") ?? "remote") ?? .remote
        let remoteToken = KeychainStore.loadSecret(account: "api-token-remote")
        remoteConfiguration = APIConfiguration(
            baseURLString: defaults.string(forKey: "wee.baseURL") ?? APIConfiguration.defaults.baseURLString,
            token: remoteToken.isEmpty ? Self.launchToken : remoteToken,
            identity: defaults.string(forKey: "wee.identity") ?? APIConfiguration.defaults.identity,
            channel: defaults.string(forKey: "wee.channel") ?? APIConfiguration.defaults.channel,
            allowInsecureTLS: defaults.object(forKey: "wee.allowInsecureTLS") as? Bool ?? APIConfiguration.defaults.allowInsecureTLS
        )
        localConfiguration = APIConfiguration(
            baseURLString: defaults.string(forKey: "wee.local.baseURL") ?? "http://127.0.0.1:8001",
            token: KeychainStore.loadSecret(account: "api-token-local"),
            identity: defaults.string(forKey: "wee.local.identity") ?? "local-macos",
            channel: defaults.string(forKey: "wee.local.channel") ?? "webui",
            allowInsecureTLS: defaults.object(forKey: "wee.local.allowInsecureTLS") as? Bool ?? false
        )
        localServiceConfiguration = LocalAPIServiceConfiguration(
            executablePath: defaults.string(forKey: "wee.localService.executable") ?? LocalAPIServiceConfiguration.defaults.executablePath,
            arguments: defaults.string(forKey: "wee.localService.arguments") ?? LocalAPIServiceConfiguration.defaults.arguments,
            workingDirectory: defaults.string(forKey: "wee.localService.workingDirectory") ?? LocalAPIServiceConfiguration.defaults.workingDirectory,
            autoStart: defaults.bool(forKey: "wee.localService.autoStart"),
            repositoryURL: defaults.string(forKey: "wee.localService.repositoryURL") ?? LocalAPIServiceConfiguration.defaults.repositoryURL,
            checkoutDirectory: defaults.string(forKey: "wee.localService.checkoutDirectory") ?? LocalAPIServiceConfiguration.defaults.checkoutDirectory
        )
        localModelConfiguration = LocalModelConfiguration(
            selectedModel: defaults.string(forKey: "wee.localModels.selected") ?? LocalModelConfiguration.defaults.selectedModel,
            autoStartRunner: defaults.object(forKey: "wee.localModels.autoStart") as? Bool ?? LocalModelConfiguration.defaults.autoStartRunner
        )
        localOpenRouterAPIKey = KeychainStore.loadSecret(account: Self.localOpenRouterKeyAccount)
        selectedAgent = defaults.string(forKey: "wee.selectedAgent.\(activeEnvironment.rawValue)")
            ?? defaults.string(forKey: "wee.selectedAgent") ?? "orchestrator"
        selectedRuntime = defaults.string(forKey: "wee.selectedRuntime") ?? ""
        selectedModel = defaults.string(forKey: "wee.selectedModel") ?? ""
        selectedPermissionMode = defaults.string(forKey: "wee.selectedPermissionMode") ?? "restricted"
        kanbanEnabled = defaults.object(forKey: "wee.kanban.enabled") as? Bool ?? true
        let storedTextSizeIndex = defaults.object(forKey: Self.appTextSizeKey) as? Int ?? Self.defaultTextSizeIndex
        appTextSize = Self.textSizeSteps.indices.contains(storedTextSizeIndex)
            ? Self.textSizeSteps[storedTextSizeIndex]
            : Self.textSizeSteps[Self.defaultTextSizeIndex]
        remoteSSHHost = defaults.string(forKey: "wee.remoteSSH.host") ?? ""
        remoteSSHKeyPath = defaults.string(forKey: "wee.remoteSSH.keyPath") ?? ""
        remoteSSHRepositoryURL = defaults.string(forKey: "wee.remoteSSH.repositoryURL") ?? remoteSSHRepositoryURL
        remoteSSHCheckoutDirectory = defaults.string(forKey: "wee.remoteSSH.checkoutDirectory") ?? remoteSSHCheckoutDirectory
        userAvatarImagePath = defaults.string(forKey: "wee.userAvatarImagePath") ?? ""
    }

    var client: WeeAPIClient {
        WeeAPIClient(configuration: configuration)
    }

    func client(for environment: WeeEnvironment) -> WeeAPIClient {
        WeeAPIClient(configuration: environment == .local ? localConfiguration : remoteConfiguration)
    }

    var isAuthenticated: Bool {
        hasAuthToken
    }

    var isCurrentSessionStreaming: Bool {
        guard let currentSessionID else { return false }
        return streamTranscripts.isStreaming(ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID))
    }

    func isSessionStreaming(_ sessionID: String) -> Bool {
        _ = streamingRevision
        return streamTranscripts.isStreaming(ChatTranscriptKey(environment: activeEnvironment, sessionID: sessionID))
    }

    private func markStreamingChanged() {
        streamingRevision &+= 1
    }

    private var textSizeIndex: Int {
        Self.textSizeSteps.firstIndex(of: appTextSize) ?? Self.defaultTextSizeIndex
    }

    var canIncreaseTextSize: Bool { textSizeIndex < Self.textSizeSteps.count - 1 }
    var canDecreaseTextSize: Bool { textSizeIndex > 0 }

    var textSizeLabel: String {
        switch appTextSize {
        case .xSmall: "Smallest"
        case .small: "Smaller"
        case .medium: "Small"
        case .large: "Default"
        case .xLarge: "Larger"
        case .xxLarge: "Large"
        case .xxxLarge: "Largest"
        default: "Default"
        }
    }

    func increaseTextSize() { setTextSizeIndex(textSizeIndex + 1) }
    func decreaseTextSize() { setTextSizeIndex(textSizeIndex - 1) }
    func resetTextSize() { setTextSizeIndex(Self.defaultTextSizeIndex) }

    private func setTextSizeIndex(_ index: Int) {
        let clamped = min(max(index, 0), Self.textSizeSteps.count - 1)
        appTextSize = Self.textSizeSteps[clamped]
        defaults.set(clamped, forKey: Self.appTextSizeKey)
        // UserDefaults normally flushes asynchronously. Persist immediately so
        // changing this control and immediately quitting the app is durable.
        defaults.synchronize()
    }

    /// Issue #25: user avatar bubble. Stored as a copied file under
    /// Application Support (not the original picked URL, which may be a
    /// sandboxed/temporary security-scoped location) with only the resolved
    /// path persisted — never the image data itself — in UserDefaults.
    var userAvatarImage: NSImage? {
        guard !userAvatarImagePath.isEmpty else { return nil }
        return NSImage(contentsOfFile: userAvatarImagePath)
    }

    func setUserAvatarImage(from sourceURL: URL) {
        let fileManager = FileManager.default
        guard let directory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WeeOrchestrator", isDirectory: true) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let destination = directory.appendingPathComponent("user-avatar.\(ext)")
        try? fileManager.removeItem(at: destination)
        guard (try? fileManager.copyItem(at: sourceURL, to: destination)) != nil else { return }

        userAvatarImagePath = destination.path
        defaults.set(destination.path, forKey: "wee.userAvatarImagePath")
    }

    func clearUserAvatarImage() {
        if !userAvatarImagePath.isEmpty {
            try? FileManager.default.removeItem(atPath: userAvatarImagePath)
        }
        userAvatarImagePath = ""
        defaults.removeObject(forKey: "wee.userAvatarImagePath")
    }

    func setKanbanEnabled(_ enabled: Bool) {
        kanbanEnabled = enabled
        defaults.set(enabled, forKey: "wee.kanban.enabled")
        if !enabled {
            kanbanBoard = nil
            kanbanStatusMessage = nil
        }
    }

    var currentQueuedChatMessages: [QueuedChatMessage] {
        _ = chatQueueRevision
        guard let currentSessionID else { return [] }
        return queuedChatMessages.messages(for: ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID))
    }

    var currentChatQueueCount: Int { currentQueuedChatMessages.count }
    var isShowingRecentChatWindow: Bool { chatHistoryTotal > chatMessages.count }

    func bootstrap() async {
        installWeeCLI()
        await updateManagedWeeCLI()
        await requestNotificationPermission()
        if localModelConfiguration.autoStartRunner { await startOllama() }
        if localServiceConfiguration.autoStart {
            await startLocalAPI()
            await waitForLocalAPIReadiness()
        }
        await refreshAgentSources()
        await refreshAll()
        await refreshOllamaStatus()
        Task { [weak self] in
            await self?.checkForAppUpdate()
        }
        startHourlyUpdateCheckLoopIfNeeded()
        startBackgroundTaskAutoRefreshLoopIfNeeded()
    }

    func installWeeCLI() {
        do {
            let installation = try WeeCLIInstaller.install(
                workingDirectory: localServiceConfiguration.workingDirectory,
                checkoutDirectory: localServiceConfiguration.checkoutDirectory
            )
            weeCLIInstallationStatus = "Available at \(installation.launcherURL.path)"
        } catch {
            weeCLIInstallationStatus = "CLI install failed: \(error.localizedDescription)"
        }
    }

    func updateManagedWeeCLI() async {
        weeCLIInstallationStatus = "Updating managed Wee CLI…"
        do {
            let checkout = try await Task.detached(priority: .utility) {
                try WeeCLIInstaller.updateManagedRuntime()
            }.value
            installWeeCLI()
            weeCLIInstallationStatus = "Current CLI installed from \(checkout.path)"
        } catch {
            installWeeCLI()
            weeCLIInstallationStatus = "CLI update failed; launcher retained: \(error.localizedDescription)"
        }
    }

    /// Issue #20: background task status previously only updated on a
    /// manual refresh. Poll quietly (no isLoading spinner, no other state
    /// touched) so a task's status catches up within a minute on its own.
    /// Same duplicate-loop guard pattern as the hourly update check, for the
    /// same reason (bootstrap() re-runs per window against the shared model).
    func startBackgroundTaskAutoRefreshLoopIfNeeded() {
        guard backgroundTaskAutoRefreshTask == nil else { return }
        backgroundTaskAutoRefreshLoopStartCount += 1
        backgroundTaskAutoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.refreshBackgroundTasksQuietly()
            }
        }
    }

    private func refreshBackgroundTasksQuietly() async {
        guard !configuration.token.isEmpty, let newTasks = try? await client.backgroundTasks() else { return }
        let ordered = BackgroundTaskOrdering.newestFirst(newTasks)
        notifyCompletedTasks(old: tasks, new: ordered)
        tasks = ordered
    }

    /// Issue #19: check for updates automatically once an hour, not just at
    /// launch or on a manual click. Guarded so opening additional windows
    /// (each re-runs `bootstrap()` against the same shared model) doesn't
    /// spawn duplicate loops.
    func startHourlyUpdateCheckLoopIfNeeded() {
        guard hourlyUpdateCheckTask == nil else { return }
        hourlyUpdateCheckLoopStartCount += 1
        hourlyUpdateCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                guard !Task.isCancelled else { return }
                await self?.checkForAppUpdate()
            }
        }
    }

    func checkForAppUpdate(showResult: Bool = false) async {
        guard !isCheckingForAppUpdate else { return }
        guard let currentVersion = currentAppVersion else {
            if showResult { appUpdateStatus = "Unable to read this app's version." }
            return
        }

        isCheckingForAppUpdate = true
        defer { isCheckingForAppUpdate = false }

        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/leprachuan/Wee-Orchestrator/releases?per_page=100")!)
            request.setValue("WeeOrchestrator-macOS", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "WeeUpdate", code: 1, userInfo: [NSLocalizedDescriptionKey: "The release server did not accept the update check."])
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            availableAppUpdate = MacAppReleaseSelector.latestUpdate(from: releases, newerThan: currentVersion)
            if let availableAppUpdate {
                appUpdateStatus = "Wee Orchestrator \(availableAppUpdate.version) is ready to install."
            } else if showResult {
                appUpdateStatus = "You're up to date (v\(currentVersion))."
            }
        } catch {
            if showResult {
                appUpdateStatus = "Unable to check for updates: \(error.localizedDescription)"
            }
        }
    }

    func installAvailableAppUpdate() async {
        guard let update = availableAppUpdate else { return }
        guard !isInstallingAppUpdate else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            appUpdateStatus = "This build is not installed as an app bundle. Download the release manually."
            return
        }
        guard FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path) else {
            appUpdateStatus = "Move Wee Orchestrator to a writable Applications folder, then try again."
            return
        }

        isInstallingAppUpdate = true
        appUpdateStatus = "Downloading Wee Orchestrator \(update.version)…"

        do {
            let stagingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("WeeOrchestrator-Update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            let archiveURL = stagingDirectory.appendingPathComponent("WeeOrchestrator.zip")
            let (temporaryArchiveURL, archiveResponse) = try await URLSession.shared.download(for: URLRequest(url: update.archiveURL))
            guard let http = archiveResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "WeeUpdate", code: 2, userInfo: [NSLocalizedDescriptionKey: "The app archive could not be downloaded."])
            }
            try FileManager.default.moveItem(at: temporaryArchiveURL, to: archiveURL)

            let expectedChecksum = try await updateChecksum(for: update)
            let archiveData = try Data(contentsOf: archiveURL)
            let actualChecksum = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
            guard actualChecksum == expectedChecksum else {
                throw NSError(domain: "WeeUpdate", code: 3, userInfo: [NSLocalizedDescriptionKey: "The downloaded app did not match its published checksum."])
            }

            let expandedDirectory = stagingDirectory.appendingPathComponent("expanded", isDirectory: true)
            try FileManager.default.createDirectory(at: expandedDirectory, withIntermediateDirectories: true)
            _ = try await runCommand(executable: "/usr/bin/ditto", arguments: ["-x", "-k", archiveURL.path, expandedDirectory.path])
            guard let replacementAppURL = try FileManager.default.contentsOfDirectory(
                at: expandedDirectory,
                includingPropertiesForKeys: nil
            ).first(where: { $0.pathExtension == "app" }) else {
                throw NSError(domain: "WeeUpdate", code: 4, userInfo: [NSLocalizedDescriptionKey: "The update archive did not contain WeeOrchestrator.app."])
            }
            guard Bundle(url: replacementAppURL)?.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let replacementVersion = Bundle(url: replacementAppURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  AppSemanticVersion(replacementVersion) == update.version else {
                throw NSError(domain: "WeeUpdate", code: 5, userInfo: [NSLocalizedDescriptionKey: "The update archive is not the expected Wee Orchestrator version."])
            }
            _ = try await runCommand(executable: "/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", replacementAppURL.path])

            try scheduleAppReplacement(source: replacementAppURL, target: Bundle.main.bundleURL, stagingDirectory: stagingDirectory)
            appUpdateStatus = "Installing Wee Orchestrator \(update.version)…"
            NSApp.terminate(nil)
        } catch {
            isInstallingAppUpdate = false
            appUpdateStatus = "Update failed: \(error.localizedDescription)"
        }
    }

    private var currentAppVersion: AppSemanticVersion? {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        return AppSemanticVersion(version)
    }

    private func updateChecksum(for update: MacAppUpdate) async throws -> String {
        if let checksumURL = update.checksumURL {
            let (data, response) = try await URLSession.shared.data(from: checksumURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let checksum = String(data: data, encoding: .utf8)?
                    .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
                    .first,
                  checksum.count == 64,
                  checksum.allSatisfy({ $0.isHexDigit }) else {
                throw NSError(domain: "WeeUpdate", code: 6, userInfo: [NSLocalizedDescriptionKey: "The published update checksum is invalid."])
            }
            return String(checksum).lowercased()
        }
        if let bodyChecksum = update.bodyChecksum { return bodyChecksum }
        throw NSError(domain: "WeeUpdate", code: 7, userInfo: [NSLocalizedDescriptionKey: "This release has no checksum, so it cannot be installed automatically."])
    }

    private func scheduleAppReplacement(source: URL, target: URL, stagingDirectory: URL) throws {
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", source.pathExtension == "app",
              FileManager.default.isWritableFile(atPath: parent.path) else {
            throw NSError(domain: "WeeUpdate", code: 8, userInfo: [NSLocalizedDescriptionKey: "The installed app location is not writable."])
        }

        let scriptURL = stagingDirectory.appendingPathComponent("install-update.sh")
        let script = Self.appReplacementScript
        try script.data(using: .utf8)?.write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            scriptURL.path,
            target.path,
            source.path,
            String(ProcessInfo.processInfo.processIdentifier)
        ]
        try process.run()
    }

    /// The app being updated must be gone before its bundle is moved.  Opening
    /// a replacement while its predecessor is still alive just activates the
    /// old process, which leaves the updater UI permanently on "Installing…".
    static let appReplacementScript = """
        #!/bin/sh
        set -eu
        target="$1"
        source="$2"
        old_pid="$3"
        backup="${target}.previous"
        attempts=0
        while /bin/kill -0 "$old_pid" 2>/dev/null; do
          if [ "$attempts" -ge 30 ]; then
            exit 1
          fi
          attempts=$((attempts + 1))
          sleep 1
        done
        rm -rf "$backup"
        if [ -d "$target" ]; then mv "$target" "$backup"; fi
        if ! /usr/bin/ditto "$source" "$target"; then
          if [ -d "$backup" ]; then mv "$backup" "$target"; fi
          exit 1
        fi
        /usr/bin/open "$target"
        rm -rf "$backup"
        """

    private func waitForLocalAPIReadiness() async {
        for _ in 0..<12 {
            if let health = try? await client(for: .local).health(), health.status == "ok" {
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func saveConfiguration() {
        defaults.set(textSizeIndex, forKey: Self.appTextSizeKey)
        defaults.set(activeEnvironment.rawValue, forKey: "wee.activeEnvironment")
        defaults.set(remoteConfiguration.baseURLString, forKey: "wee.baseURL")
        defaults.set(remoteConfiguration.identity, forKey: "wee.identity")
        defaults.set(remoteConfiguration.channel, forKey: "wee.channel")
        defaults.set(remoteConfiguration.allowInsecureTLS, forKey: "wee.allowInsecureTLS")
        defaults.set(localConfiguration.baseURLString, forKey: "wee.local.baseURL")
        defaults.set(localConfiguration.identity, forKey: "wee.local.identity")
        defaults.set(localConfiguration.channel, forKey: "wee.local.channel")
        defaults.set(localConfiguration.allowInsecureTLS, forKey: "wee.local.allowInsecureTLS")
        defaults.set(localServiceConfiguration.executablePath, forKey: "wee.localService.executable")
        defaults.set(localServiceConfiguration.arguments, forKey: "wee.localService.arguments")
        defaults.set(localServiceConfiguration.workingDirectory, forKey: "wee.localService.workingDirectory")
        defaults.set(localServiceConfiguration.autoStart, forKey: "wee.localService.autoStart")
        defaults.set(localServiceConfiguration.repositoryURL, forKey: "wee.localService.repositoryURL")
        defaults.set(localServiceConfiguration.checkoutDirectory, forKey: "wee.localService.checkoutDirectory")
        defaults.set(localModelConfiguration.selectedModel, forKey: "wee.localModels.selected")
        defaults.set(localModelConfiguration.autoStartRunner, forKey: "wee.localModels.autoStart")
        defaults.set(selectedAgent, forKey: "wee.selectedAgent.\(activeEnvironment.rawValue)")
        defaults.set(selectedRuntime, forKey: "wee.selectedRuntime")
        defaults.set(selectedModel, forKey: "wee.selectedModel")
        defaults.set(selectedPermissionMode, forKey: "wee.selectedPermissionMode")
        defaults.set(remoteSSHHost, forKey: "wee.remoteSSH.host")
        defaults.set(remoteSSHKeyPath, forKey: "wee.remoteSSH.keyPath")
        defaults.set(remoteSSHRepositoryURL, forKey: "wee.remoteSSH.repositoryURL")
        defaults.set(remoteSSHCheckoutDirectory, forKey: "wee.remoteSSH.checkoutDirectory")
        KeychainStore.saveSecret(remoteConfiguration.token, account: "api-token-remote")
        KeychainStore.saveSecret(localConfiguration.token, account: "api-token-local")
        KeychainStore.saveSecret(localOpenRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), account: Self.localOpenRouterKeyAccount)
    }

    func loadLocalKanbanSettings() async {
        guard !localConfiguration.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            localKanbanSettingsStatus = "Add a Local API token to configure the Kanban repository."
            return
        }

        do {
            let settings = try await client(for: .local).kanbanSettings()
            localKanbanRepository = settings.githubRepo
            localKanbanEffectiveRepository = settings.effectiveRepo
            localKanbanFallbackRepository = settings.fallbackRepo
            localKanbanSettingsStatus = ""
        } catch {
            localKanbanSettingsStatus = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
        }
    }

    func saveLocalKanbanSettings() async -> Bool {
        let repository = localKanbanRepository.trimmingCharacters(in: .whitespacesAndNewlines)
        isSavingLocalKanbanSettings = true
        defer { isSavingLocalKanbanSettings = false }

        do {
            let settings = try await client(for: .local).saveKanbanSettings(githubRepo: repository)
            localKanbanRepository = settings.githubRepo
            localKanbanEffectiveRepository = settings.effectiveRepo
            localKanbanFallbackRepository = settings.fallbackRepo
            localKanbanSettingsStatus = repository.isEmpty
                ? "Repository override cleared. Using the checkout's Git remote."
                : "Kanban repository saved."
            if activeEnvironment == .local {
                await loadKanbanBoard()
            }
            return true
        } catch {
            localKanbanSettingsStatus = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            return false
        }
    }

    func switchEnvironment(to environment: WeeEnvironment) async {
        guard environment != activeEnvironment else { return }
        defaults.set(selectedAgent, forKey: "wee.selectedAgent.\(activeEnvironment.rawValue)")
        activeEnvironment = environment
        selectedAgent = defaults.string(forKey: "wee.selectedAgent.\(environment.rawValue)")
            ?? agents(for: environment).first?.name ?? "orchestrator"
        currentSessionID = nil
        chatMessages = [ChatMessage(role: .system, text: "Switched to the \(environment.title) environment.")]
        health = nil
        appConfig = nil
        tasks = []
        scheduledJobs = []
        historySessions = []
        kanbanBoard = nil
        agents = agents(for: environment)
        saveConfiguration()
        await refreshAll()
    }

    func agents(for environment: WeeEnvironment) -> [AgentSummary] {
        environment == .local ? localAgents : remoteAgents
    }

    func refreshAgentSources() async {
        async let localResult: [AgentSummary]? = try? client(for: .local).agents()
        async let remoteResult: [AgentSummary]? = try? client(for: .remote).agents()
        if let values = await localResult { localAgents = values }
        if let values = await remoteResult { remoteAgents = values }
        agents = agents(for: activeEnvironment)
    }

    func testConnection(_ environment: WeeEnvironment) async -> String {
        do {
            let response = try await client(for: environment).health()
            return response.status == "ok" ? "Connected" : "Status: \(response.status)"
        } catch {
            return error.localizedDescription
        }
    }

    func cloneLocalAPISource() async {
        let repository = localServiceConfiguration.repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = Self.expandedPath(localServiceConfiguration.checkoutDirectory)
        guard !repository.isEmpty else {
            localSourceStatus = "Repository URL is required"
            return
        }
        guard !destination.isEmpty else {
            localSourceStatus = "Checkout folder is required"
            return
        }
        guard !FileManager.default.fileExists(atPath: destination) || (try? FileManager.default.contentsOfDirectory(atPath: destination).isEmpty) == true else {
            localSourceStatus = "Checkout folder already exists and is not empty"
            return
        }

        isLocalSourceWorking = true
        localSourceStatus = "Cloning…"
        localSourceOutput = ""
        defer { isLocalSourceWorking = false }

        do {
            let output = try await runGit(["clone", "--depth", "1", repository, destination])
            localSourceOutput = output
            localServiceConfiguration.checkoutDirectory = destination
            localServiceConfiguration.workingDirectory = destination
            saveConfiguration()
            _ = try ensureLocalAgentsConfiguration()
            guard await bootstrapLocalAPIEnvironment(at: destination) else { return }
            localSourceStatus = "Clone, local agent configuration, and dependency setup complete"
        } catch {
            localSourceStatus = "Clone failed: \(error.localizedDescription)"
        }
    }

    func pullLatestLocalAPISource() async {
        let checkout = Self.expandedPath(localServiceConfiguration.checkoutDirectory)
        guard FileManager.default.fileExists(atPath: "\(checkout)/.git") else {
            localSourceStatus = "Choose an existing Git checkout first"
            return
        }

        isLocalSourceWorking = true
        localSourceStatus = "Pulling latest…"
        localSourceOutput = ""
        defer { isLocalSourceWorking = false }

        do {
            let output = try await runGit(["-C", checkout, "pull", "--ff-only"])
            localSourceOutput = output
            localServiceConfiguration.workingDirectory = checkout
            saveConfiguration()
            guard await bootstrapLocalAPIEnvironment(at: checkout) else { return }
            localSourceStatus = output.localizedCaseInsensitiveContains("already up to date") ? "Already up to date; dependencies refreshed" : "Updated to latest; dependencies refreshed"
        } catch {
            localSourceStatus = "Update failed: \(error.localizedDescription)"
        }
    }

    private func runGit(_ arguments: [String]) async throws -> String {
        try await runCommand(executable: "/usr/bin/git", arguments: arguments)
    }

    private func runCommand(executable: String, arguments: [String], workingDirectory: String? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let output = GitOutputCollector()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            }
            process.standardOutput = pipe
            process.standardError = pipe
            process.environment = ProcessInfo.processInfo.environment.merging([
                "GIT_TERMINAL_PROMPT": "0"
            ]) { _, configured in configured }
            pipe.fileHandleForReading.readabilityHandler = { handle in
                output.append(handle.availableData)
            }
            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                output.append(pipe.fileHandleForReading.readDataToEndOfFile())
                let text = output.text()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "WeeGit",
                        code: Int(process.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: text.isEmpty ? "git exited with status \(process.terminationStatus)" : text]
                    ))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private var ollamaExecutable: String? {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/usr/bin/ollama"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
    }

    var isOllamaInstalled: Bool { ollamaExecutable != nil }
    var localModelMemoryGB: Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }

    func refreshOllamaStatus() async {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let tags = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            ollamaModels = tags.models.map { OllamaModelSummary(name: $0.name, sizeBytes: $0.size) }.sorted { $0.name < $1.name }
            for downloaded in ollamaModels {
                if let catalogMatch = curatedModels.first(where: { $0.name == downloaded.name }) {
                    knownModelContextWindows[downloaded.name] = catalogMatch.contextWindow
                }
            }
            if !localModelConfiguration.selectedModel.isEmpty,
               !ollamaModels.contains(where: { $0.name == localModelConfiguration.selectedModel }) {
                localModelConfiguration.selectedModel = ""
                saveConfiguration()
            }
            ollamaStatus = "Running · \(ollamaModels.count) downloaded"
        } catch {
            ollamaModels = []
            ollamaStatus = isOllamaInstalled ? "Installed · not running" : "Not installed"
        }
    }

    func installOllama() async {
        isOllamaWorking = true
        ollamaStatus = "Installing Ollama…"
        defer { isOllamaWorking = false }
        do {
            let command = "if command -v brew >/dev/null 2>&1; then brew install ollama; else curl -fsSL https://ollama.com/install.sh | sh; fi"
            let output = try await runCommand(executable: "/bin/zsh", arguments: ["-lc", command])
            localSourceOutput = String((localSourceOutput + output).suffix(20_000))
            await refreshOllamaStatus()
        } catch {
            ollamaStatus = "Install failed: \(error.localizedDescription)"
        }
    }

    func startOllama() async {
        if ollamaStatus.hasPrefix("Running") { return }
        guard let executable = ollamaExecutable else {
            ollamaStatus = "Install Ollama first"
            return
        }
        isOllamaWorking = true
        defer { isOllamaWorking = false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.environment = ProcessInfo.processInfo.environment
        do {
            try process.run()
            ollamaProcess = process
        } catch {
            // The Ollama macOS app may already own the server process.
        }
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(500))
            await refreshOllamaStatus()
            if ollamaStatus.hasPrefix("Running") {
                // The local API may have started (or last polled) before the
                // runner was up, so its Ollama discovery cache could be empty.
                if isLocalServiceRunning { restartLocalAPI() }
                return
            }
        }
    }

    func stopOllama() {
        ollamaProcess?.terminate()
        ollamaProcess = nil
        ollamaStatus = "Installed · stopped"
    }

    func pullOllamaModel(_ model: LocalModelCatalogItem) async {
        guard model.contextWindow >= 64_000 else {
            ollamaStatus = "\(model.displayName) does not meet the 64K context requirement"
            return
        }
        guard let executable = ollamaExecutable else {
            ollamaStatus = "Install Ollama first"
            return
        }
        isOllamaWorking = true
        ollamaStatus = "Downloading \(model.displayName)…"
        defer { isOllamaWorking = false }
        do {
            let output = try await runCommand(executable: executable, arguments: ["pull", model.name])
            localSourceOutput = String((localSourceOutput + output).suffix(20_000))
            knownModelContextWindows[model.name] = model.contextWindow
            await refreshOllamaStatus()
            await refreshLocalWeeCatalog(afterModelChange: model.name)
        } catch {
            ollamaStatus = "Download failed: \(error.localizedDescription)"
        }
    }

    /// Refreshes `curatedModels` with live Ollama registry metadata for the Qwen 3.6 and
    /// Gemma 4 families (per issue #392), sorted so the best fit for this Mac's available
    /// memory sorts first. Falls back to the static seed list when the registry can't be reached.
    func refreshCuratedModels() async {
        var liveModels: [LocalModelCatalogItem] = []
        for baseName in ["gemma4", "qwen3.6"] {
            guard let variants = try? await OllamaRegistryClient.fetchTagVariants(baseName: baseName), !variants.isEmpty else { continue }
            liveModels.append(contentsOf: variants.map(Self.catalogItem(from:)))
        }
        guard !liveModels.isEmpty else {
            curatedModels = Self.sortedByMemoryFit(LocalModelCatalogItem.recommended, memoryGB: localModelMemoryGB)
            return
        }
        let staticExtras = LocalModelCatalogItem.recommended.filter { item in
            !liveModels.contains { $0.name == item.name } && !item.name.hasPrefix("gemma4") && !item.name.hasPrefix("qwen3.6")
        }
        curatedModels = Self.sortedByMemoryFit(liveModels + staticExtras, memoryGB: localModelMemoryGB)
    }

    private static func catalogItem(from registryModel: OllamaRegistryModel) -> LocalModelCatalogItem {
        let sizeGB = registryModel.sizeGB ?? 0
        let family = registryModel.baseName.hasPrefix("qwen") ? "Qwen 3.6" : "Gemma 4"
        return LocalModelCatalogItem(
            name: registryModel.fullTag,
            displayName: "\(family) \(registryModel.tag)".trimmingCharacters(in: .whitespaces),
            parameterSize: registryModel.modalities ?? "—",
            contextWindow: registryModel.contextWindow,
            estimatedDownloadGB: sizeGB,
            description: "Live from the Ollama registry · \(registryModel.contextWindow / 1_000)K context · ~\(String(format: "%.1f", sizeGB)) GB download."
        )
    }

    private static func sortedByMemoryFit(_ items: [LocalModelCatalogItem], memoryGB: Double) -> [LocalModelCatalogItem] {
        guard memoryGB > 0 else { return items }
        return items.sorted { $0.estimatedDownloadGB / memoryGB < $1.estimatedDownloadGB / memoryGB }
    }

    /// Searches the live Ollama registry (ollama.com) for models matching `query`, restricted
    /// to variants with a 64K+ context window. Empty query clears results.
    func searchOllamaRegistry(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            registrySearchResults = []
            registrySearchStatus = ""
            return
        }
        isSearchingRegistry = true
        registrySearchStatus = "Searching Ollama registry…"
        defer { isSearchingRegistry = false }
        do {
            let results = try await OllamaRegistryClient.search(query: trimmed)
            registrySearchResults = results
            registrySearchStatus = results.isEmpty
                ? "No 64K+ context models found on the registry for “\(trimmed)”."
                : "\(results.count) 64K+ context model\(results.count == 1 ? "" : "s") found."
        } catch {
            registrySearchResults = []
            registrySearchStatus = "Registry search failed: \(error.localizedDescription)"
        }
    }

    func pullRegistryModel(_ registryModel: OllamaRegistryModel) async {
        guard registryModel.contextWindow >= OllamaRegistryClient.minimumContextWindow else {
            ollamaStatus = "\(registryModel.displayName) does not meet the 64K context requirement"
            return
        }
        guard let executable = ollamaExecutable else {
            ollamaStatus = "Install Ollama first"
            return
        }
        isOllamaWorking = true
        ollamaStatus = "Downloading \(registryModel.displayName)…"
        defer { isOllamaWorking = false }
        do {
            let output = try await runCommand(executable: executable, arguments: ["pull", registryModel.fullTag])
            localSourceOutput = String((localSourceOutput + output).suffix(20_000))
            knownModelContextWindows[registryModel.fullTag] = registryModel.contextWindow
            await refreshOllamaStatus()
            await refreshLocalWeeCatalog(afterModelChange: registryModel.fullTag)
        } catch {
            ollamaStatus = "Download failed: \(error.localizedDescription)"
        }
    }

    /// Context window for a downloaded model if known from a prior catalog/registry/custom
    /// pull in this session. Used to gate the "Use Model" action for downloaded-but-uncataloged
    /// models against the 64K requirement.
    func knownContextWindow(forDownloadedModel name: String) -> Int? {
        knownModelContextWindows[name]
    }

    func pullCustomOllamaModel(tag: String, declaredContextWindow: Int) async {
        let name = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ollamaStatus = "Enter an Ollama registry model tag"
            return
        }
        guard declaredContextWindow >= 64_000 else {
            ollamaStatus = "Only models with a declared 64K+ context window can be downloaded"
            return
        }
        guard let executable = ollamaExecutable else {
            ollamaStatus = "Install Ollama first"
            return
        }
        isOllamaWorking = true
        ollamaStatus = "Downloading \(name)…"
        defer { isOllamaWorking = false }
        do {
            let output = try await runCommand(executable: executable, arguments: ["pull", name])
            localSourceOutput = String((localSourceOutput + output).suffix(20_000))
            knownModelContextWindows[name] = declaredContextWindow
            await refreshOllamaStatus()
            localModelConfiguration.selectedModel = name
            saveConfiguration()
            await refreshLocalWeeCatalog(afterModelChange: name)
        } catch {
            ollamaStatus = "Download failed: \(error.localizedDescription)"
        }
    }

    func removeOllamaModel(_ model: OllamaModelSummary) async {
        guard let executable = ollamaExecutable else { return }
        isOllamaWorking = true
        defer { isOllamaWorking = false }
        do {
            _ = try await runCommand(executable: executable, arguments: ["rm", model.name])
            if localModelConfiguration.selectedModel == model.name {
                localModelConfiguration.selectedModel = LocalModelConfiguration.defaults.selectedModel
            }
            saveConfiguration()
            await refreshOllamaStatus()
            // Match the download path: force the local API to drop its cached
            // Ollama inventory so the removed model stops being offered.
            await refreshLocalWeeCatalog(afterModelChange: model.name, shouldContainModel: false)
        } catch {
            ollamaStatus = "Remove failed: \(error.localizedDescription)"
        }
    }

    func selectLocalModel(_ model: LocalModelCatalogItem) {
        selectLocalModel(name: model.name, contextWindow: model.contextWindow)
    }

    func selectLocalModel(name: String, contextWindow: Int) {
        guard contextWindow >= 64_000 else { return }
        guard ollamaModels.contains(where: { $0.name == name }) else {
            ollamaStatus = "Download \(name) before selecting it"
            return
        }
        localModelConfiguration.selectedModel = name
        saveConfiguration()
        Task { @MainActor [weak self] in
            await self?.refreshLocalWeeCatalog(afterModelChange: name)
        }
    }

    /// Reads a runtime's ordered model list from the local API checkout. The
    /// manifest is deliberately edited here rather than through the connected
    /// API so this can never change a Remote environment's catalog. Wee is
    /// excluded because its list is assembled dynamically from local Ollama and
    /// OpenRouter discovery.
    func loadLocalModelManifest(runtime: String) -> [String] {
        let trimmedRuntime = runtime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedRuntime != "wee" else {
            localModelManifestStatus = "The Wee catalog is discovered from Ollama and OpenRouter, so it is not edited here."
            return []
        }

        let manifestURL = localModelManifestURL()
        do {
            let data = try Data(contentsOf: manifestURL)
            guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let runtimes = document["runtimes"] as? [String: Any] else {
                localModelManifestStatus = "No runtime catalog was found in model-manifest.json."
                return []
            }
            localModelManifestRuntimes = runtimes.keys
                .map { $0.lowercased() }
                .filter { $0 != "wee" }
                .sorted()
            guard let models = runtimes[trimmedRuntime] as? [String] else {
                localModelManifestStatus = "No \(trimmedRuntime) list was found in model-manifest.json."
                return []
            }
            localModelManifestStatus = "Loaded \(models.count) \(trimmedRuntime) model\(models.count == 1 ? "" : "s")"
            return models
        } catch {
            localModelManifestStatus = "Could not read \(manifestURL.lastPathComponent): \(error.localizedDescription)"
            return []
        }
    }

    /// Atomically persists a normalized model list while preserving the rest of
    /// the API's manifest (including other runtime catalogs and notes).
    func saveLocalModelManifest(runtime: String, models: [String]) async -> Bool {
        let trimmedRuntime = runtime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedRuntime != "wee" else {
            localModelManifestStatus = "The Wee catalog is discovered from Ollama and OpenRouter, so it is not edited here."
            return false
        }

        let normalized = models.reduce(into: [String]()) { result, candidate in
            let modelID = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !modelID.isEmpty, !result.contains(modelID) else { return }
            result.append(modelID)
        }
        guard !normalized.isEmpty else {
            localModelManifestStatus = "Add at least one model before saving."
            return false
        }

        let manifestURL = localModelManifestURL()
        do {
            let data = try Data(contentsOf: manifestURL)
            guard var document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                localModelManifestStatus = "model-manifest.json is not a JSON object."
                return false
            }
            var runtimes = document["runtimes"] as? [String: Any] ?? [:]
            guard runtimes[trimmedRuntime] != nil else {
                localModelManifestStatus = "\(trimmedRuntime) is not a configured local runtime."
                return false
            }
            runtimes[trimmedRuntime] = normalized
            document["runtimes"] = runtimes
            document["last_updated"] = ISO8601DateFormatter().string(from: Date())
            let formatted = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try formatted.write(to: manifestURL, options: .atomic)
            localModelManifestRuntimes = runtimes.keys
                .map { $0.lowercased() }
                .filter { $0 != "wee" }
                .sorted()
            localModelManifestStatus = "Saved \(normalized.count) \(trimmedRuntime) model\(normalized.count == 1 ? "" : "s"). No API restart is needed."

            if activeEnvironment == .local && selectedRuntime == trimmedRuntime {
                await loadAvailableModels(for: trimmedRuntime)
            }
            return true
        } catch {
            localModelManifestStatus = "Could not save model-manifest.json: \(error.localizedDescription)"
            return false
        }
    }

    private func localModelManifestURL() -> URL {
        URL(fileURLWithPath: Self.expandedPath(localServiceConfiguration.workingDirectory), isDirectory: true)
            .appendingPathComponent("model-manifest.json")
    }

    private func bootstrapLocalAPIEnvironment(at checkout: String) async -> Bool {
        let requirements = "\(checkout)/requirements.txt"
        let projectFile = "\(checkout)/pyproject.toml"
        guard FileManager.default.fileExists(atPath: requirements) || FileManager.default.fileExists(atPath: projectFile) else {
            localSourceStatus = "Dependency manifest not found in checkout"
            return false
        }

        let configuredPython = localServiceConfiguration.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let bootstrapPython = FileManager.default.isExecutableFile(atPath: configuredPython)
            ? configuredPython
            : "/usr/bin/python3"
        guard FileManager.default.isExecutableFile(atPath: bootstrapPython) else {
            localSourceStatus = "Python executable not found. Set it in Local API Service."
            return false
        }

        let venvPython = "\(checkout)/.venv/bin/python"
        isLocalSourceWorking = true
        defer { isLocalSourceWorking = false }

        do {
            var output = ""
            if !FileManager.default.isExecutableFile(atPath: venvPython) {
                localSourceStatus = "Creating local Python environment…"
                output += try await runCommand(
                    executable: bootstrapPython,
                    arguments: ["-m", "venv", ".venv"],
                    workingDirectory: checkout
                )
            }

            localSourceStatus = "Installing API dependencies…"
            let installArguments = FileManager.default.fileExists(atPath: requirements)
                ? ["-m", "pip", "install", "-r", "requirements.txt"]
                : ["-m", "pip", "install", "."]
            output += try await runCommand(
                executable: venvPython,
                arguments: installArguments,
                workingDirectory: checkout
            )
            output += await ensureGithubCopilotSDKInstalled(venvPython: venvPython, checkout: checkout)
            localSourceOutput = String((localSourceOutput + output).suffix(20_000))
            localServiceConfiguration.workingDirectory = checkout
            if configuredPython == LocalAPIServiceConfiguration.defaults.executablePath || !FileManager.default.isExecutableFile(atPath: configuredPython) {
                localServiceConfiguration.executablePath = venvPython
            }
            saveConfiguration()
            return true
        } catch {
            localSourceStatus = "Dependency setup failed: \(error.localizedDescription)"
            return false
        }
    }

    /// Issue #18: the Copilot/copilot-sdk runtimes depend on github-copilot-sdk,
    /// but it isn't reliably pinned in the backend's requirements.txt. Verify
    /// it importable in the freshly-installed venv and install it directly if
    /// not, so a fresh local API install doesn't fail at first Copilot use.
    /// Best-effort: a failure here is logged but does not fail the bootstrap,
    /// since every other runtime already installed successfully.
    private func ensureGithubCopilotSDKInstalled(venvPython: String, checkout: String) async -> String {
        let alreadyPresent = (try? await runCommand(
            executable: venvPython,
            arguments: ["-c", "import github_copilot_sdk"],
            workingDirectory: checkout
        )) != nil
        guard !alreadyPresent else { return "" }

        localSourceStatus = "Installing github-copilot-sdk…"
        do {
            let output = try await runCommand(
                executable: venvPython,
                arguments: ["-m", "pip", "install", "github-copilot-sdk"],
                workingDirectory: checkout
            )
            return "\n" + output
        } catch {
            return "\nWarning: could not install github-copilot-sdk (\(error.localizedDescription)). The Copilot/copilot-sdk runtimes may not work until it's installed manually.\n"
        }
    }

    private static func expandedPath(_ value: String) -> String {
        (value as NSString).expandingTildeInPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Issue #21: Remote API deployment over SSH

    /// Installs (clone-or-reuse + Python venv bootstrap) the API on a
    /// user-specified remote host over SSH, mirroring the local install
    /// flow (`cloneLocalAPISource` + `bootstrapLocalAPIEnvironment`) but
    /// executed remotely as a single non-interactive SSH command.
    func installRemoteAPIOverSSH() async {
        let host = remoteSSHHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let repository = remoteSSHRepositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = remoteSSHCheckoutDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            remoteSSHStatus = "Remote host is required"
            return
        }
        guard !repository.isEmpty else {
            remoteSSHStatus = "Repository URL is required"
            return
        }
        guard !directory.isEmpty else {
            remoteSSHStatus = "Remote install directory is required"
            return
        }

        isRemoteSSHWorking = true
        remoteSSHStatus = "Installing on \(host)…"
        remoteSSHOutput = ""
        defer { isRemoteSSHWorking = false }

        let script = """
        set -e
        if [ -d '\(directory)/.git' ]; then
          cd '\(directory)' && git pull
        else
          mkdir -p '\(directory)' && git clone '\(repository)' '\(directory)' && cd '\(directory)'
        fi
        python3 -m venv .venv
        .venv/bin/pip install -r requirements.txt
        """

        do {
            remoteSSHOutput = try await runSSH(script, host: host)
            remoteSSHStatus = "Install complete"
            saveConfiguration()
        } catch {
            remoteSSHStatus = "Install failed: \(error.localizedDescription)"
        }
    }

    /// Pulls latest and reinstalls dependencies in an existing remote
    /// checkout. Does not restart any remote service — service management
    /// (systemd unit name, etc.) is deployment-specific and out of scope
    /// here; this covers the code/dependency side of an update.
    func updateRemoteAPIOverSSH() async {
        let host = remoteSSHHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let directory = remoteSSHCheckoutDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            remoteSSHStatus = "Remote host is required"
            return
        }
        guard !directory.isEmpty else {
            remoteSSHStatus = "Remote install directory is required"
            return
        }

        isRemoteSSHWorking = true
        remoteSSHStatus = "Updating \(host)…"
        remoteSSHOutput = ""
        defer { isRemoteSSHWorking = false }

        let script = """
        set -e
        cd '\(directory)'
        git pull
        .venv/bin/pip install -r requirements.txt
        """

        do {
            remoteSSHOutput = try await runSSH(script, host: host)
            remoteSSHStatus = "Update complete"
            saveConfiguration()
        } catch {
            remoteSSHStatus = "Update failed: \(error.localizedDescription)"
        }
    }

    /// BatchMode disables interactive password/passphrase prompts (there's
    /// no TTY for the user to answer them from a subprocess), so auth must
    /// be key-based. accept-new auto-trusts a host's key on first contact
    /// instead of hanging on an interactive fingerprint prompt — a standard
    /// non-interactive-tooling default, not a security hardening choice.
    private func runSSH(_ remoteCommand: String, host: String) async throws -> String {
        var arguments = ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new"]
        let keyPath = Self.expandedPath(remoteSSHKeyPath)
        if !keyPath.isEmpty {
            arguments += ["-i", keyPath]
        }
        arguments.append(host)
        arguments.append(remoteCommand)
        return try await runCommand(executable: "/usr/bin/ssh", arguments: arguments)
    }

    /// The cloned repository includes its deployment agents.json. Keep the Mac's
    /// local agents outside that checkout so pulls cannot overwrite them or cause
    /// a Local service to inherit Remote agents.
    private func ensureLocalAgentsConfiguration() throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("WeeOrchestrator", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let configurationURL = directory.appendingPathComponent("local-agents.json")
        guard !fileManager.fileExists(atPath: configurationURL.path) else {
            return configurationURL
        }

        let initialConfiguration = "{\n  \"agents\": []\n}\n"
        try initialConfiguration.data(using: .utf8)?.write(to: configurationURL, options: .atomic)
        return configurationURL
    }

    /// Local API writes are authenticated too. The app owns this process, so it
    /// creates one private shared key and keeps only the token in Keychain.
    private func provisionLocalAPIAuthentication() -> String {
        var sharedKey = KeychainStore.loadSecret(account: Self.localSharedKeyAccount)
        if sharedKey.isEmpty {
            var bytes = [UInt8](repeating: 0, count: 32)
            if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess {
                sharedKey = bytes.map { String(format: "%02x", $0) }.joined()
            } else {
                sharedKey = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            }
            KeychainStore.saveSecret(sharedKey, account: Self.localSharedKeyAccount)
        }

        let token = "shared_\(sharedKey)"
        if localConfiguration.token != token {
            localConfiguration.token = token
            saveConfiguration()
        }
        return sharedKey
    }

    /// Recover an API process left behind by an earlier app launch. We only
    /// terminate a process whose command line identifies it as Wee's API;
    /// another application's listener is reported and left untouched.
    private func reclaimStaleLocalAPIPortIfNeeded() async -> String? {
        guard let url = URL(string: localConfiguration.baseURLString),
              let port = url.port else {
            return nil
        }

        let output = (try? await runCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"]
        )) ?? ""
        let processIDs = output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }

        for processID in processIDs {
            let command = (try? await runCommand(
                executable: "/bin/ps",
                arguments: ["-p", "\(processID)", "-o", "command="]
            ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard command.contains("agent_manager.py --api") else {
                return "Port \(port) is already used by another process. Change the Local API URL or stop that process."
            }

            do {
                _ = try await runCommand(executable: "/bin/kill", arguments: ["-TERM", "\(processID)"])
                localServiceLog = String((localServiceLog + "\nRecovered stale local API process \(processID).\n").suffix(20_000))
            } catch {
                return "Could not stop stale local API process \(processID): \(error.localizedDescription)"
            }
        }

        if !processIDs.isEmpty {
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(200))
                let remaining = (try? await runCommand(
                    executable: "/usr/sbin/lsof",
                    arguments: ["-nP", "-t", "-iTCP:\(port)", "-sTCP:LISTEN"]
                )) ?? ""
                if remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    break
                }
            }
        }
        return nil
    }

    func startLocalAPI() async {
        guard localAPIProcess?.isRunning != true else {
            localServiceStatus = "Already running"
            return
        }

        let executable = localServiceConfiguration.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let workingDirectory = Self.expandedPath(localServiceConfiguration.workingDirectory)
        if FileManager.default.fileExists(atPath: "\(workingDirectory)/requirements.txt"),
           !FileManager.default.isExecutableFile(atPath: "\(workingDirectory)/.venv/bin/python") {
            localServiceStatus = "Preparing Python dependencies…"
            guard await bootstrapLocalAPIEnvironment(at: workingDirectory) else {
                localServiceStatus = localSourceStatus
                return
            }
        }
        let resolvedExecutable = FileManager.default.isExecutableFile(atPath: "\(workingDirectory)/.venv/bin/python")
            && (executable == LocalAPIServiceConfiguration.defaults.executablePath || !FileManager.default.isExecutableFile(atPath: executable))
            ? "\(workingDirectory)/.venv/bin/python"
            : executable
        guard FileManager.default.isExecutableFile(atPath: resolvedExecutable) else {
            localServiceStatus = "Executable not found or not executable"
            return
        }
        guard FileManager.default.fileExists(atPath: workingDirectory) else {
            localServiceStatus = "Working directory not found"
            return
        }

        if let portError = await reclaimStaleLocalAPIPortIfNeeded() {
            localServiceStatus = portError
            return
        }

        let agentsConfigurationURL: URL
        do {
            agentsConfigurationURL = try ensureLocalAgentsConfiguration()
        } catch {
            localServiceStatus = "Could not create local agent configuration: \(error.localizedDescription)"
            return
        }
        let localSharedKey = provisionLocalAPIAuthentication()

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: resolvedExecutable)
        process.arguments = Self.parseCommandLine(localServiceConfiguration.arguments)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        process.standardOutput = pipe
        process.standardError = pipe
        var environment = ProcessInfo.processInfo.environment
        // Explicit values override anything inherited from the desktop process.
        // In particular, never let AGENT_CONFIG_FILE point Local at a shared config.
        environment["PYTHONUNBUFFERED"] = "1"
        environment["APP_ENV"] = "LOCAL"
        environment["AGENT_CONFIG_FILE"] = agentsConfigurationURL.path
        environment["API_SHARED_KEY"] = localSharedKey
        environment["WEE_OLLAMA_HOST"] = "http://127.0.0.1:11434"
        // Ollama's server default is only 4K. The Local Models screen accepts
        // 64K+ models specifically for agentic work, so request that usable
        // window on every completion the Local API sends to Ollama.
        environment["WEE_OLLAMA_CONTEXT_WINDOW"] = "65536"
        let openRouterKey = localOpenRouterAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !openRouterKey.isEmpty {
            environment["OPENROUTER_API_KEY"] = openRouterKey
        } else {
            environment.removeValue(forKey: "OPENROUTER_API_KEY")
        }
        if !localModelConfiguration.selectedModel.isEmpty {
            environment["WEE_DEFAULT_MODEL"] = "ollama/\(localModelConfiguration.selectedModel)"
        } else {
            environment.removeValue(forKey: "WEE_DEFAULT_MODEL")
        }
        // Tell the local instance's agents that a separate remote Wee
        // Orchestrator API also exists, so they don't assume this local
        // process is the only one running. Only the URL is shared — never
        // the remote token, so it can't leak into local agent context/logs.
        let remoteURL = remoteConfiguration.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteURL.isEmpty {
            environment["WEE_REMOTE_API_URL"] = remoteURL
            environment["WEE_REMOTE_API_LABEL"] = "remote (production)"
        }
        process.environment = environment

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.localServiceLog = String((self.localServiceLog + text).suffix(20_000))
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.isLocalServiceRunning = false
                self?.localServiceStatus = "Stopped (exit \(process.terminationStatus))"
                self?.localAPIProcess = nil
                self?.localLogPipe?.fileHandleForReading.readabilityHandler = nil
                self?.localLogPipe = nil
            }
        }

        do {
            try process.run()
            localAPIProcess = process
            localLogPipe = pipe
            isLocalServiceRunning = true
            localServiceStatus = "Running (PID \(process.processIdentifier))"
            saveConfiguration()
        } catch {
            localServiceStatus = "Launch failed: \(error.localizedDescription)"
        }
    }

    func stopLocalAPI() {
        guard let process = localAPIProcess, process.isRunning else {
            isLocalServiceRunning = false
            localServiceStatus = "Stopped"
            return
        }
        process.terminate()
        localServiceStatus = "Stopping…"
    }

    func restartLocalAPI() {
        stopLocalAPI()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await self?.startLocalAPI()
        }
    }

    /// Refreshes the chat picker after changing Ollama's local inventory.
    /// The Local API caches Ollama discovery for a minute, so restart the
    /// app-owned bridge, then retry until its rebuilt catalog reflects the
    /// change. This prevents a user from needing to refresh or restart Wee.
    private func refreshLocalWeeCatalog(afterModelChange modelName: String, shouldContainModel: Bool = true) async {
        let normalizedRuntime = selectedRuntime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidateIDs = Set([modelName, "ollama/\(modelName)"])

        if isLocalServiceRunning {
            restartLocalAPI()
        }

        guard activeEnvironment == .local, hasAuthToken, normalizedRuntime == "wee" else { return }

        // Allow the replacement API process to bind its port before its first
        // catalog request. If the bridge is externally managed, this still
        // refreshes the visible picker once without trying to control it.
        let attempts = isLocalServiceRunning ? 12 : 1
        for attempt in 0..<attempts {
            if attempt > 0 || isLocalServiceRunning {
                try? await Task.sleep(for: .milliseconds(500))
            }

            await loadAvailableModels(for: "wee")
            let containsModel = availableModels.contains { candidateIDs.contains($0.id) }
            if containsModel == shouldContainModel { return }
        }
    }

    private static func parseCommandLine(_ value: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in value {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
                else { current.append(character) }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty { arguments.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
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

    func refreshAll() async {
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
            if activeEnvironment == .local { localAgents = agents }
            else { remoteAgents = agents }
            if !agents.contains(where: { $0.name == selectedAgent }) {
                selectedAgent = agents.first?.name ?? "orchestrator"
            }
            applySelectionDefaults()

            if !configuration.token.isEmpty {
                async let runtimeResponse: [RuntimeEntry]? = try? client.runtimes()
                async let taskResponse: [BackgroundTaskSummary]? = try? client.backgroundTasks()
                async let sessionResponse: [HistorySessionSummary]? = try? client.historySessions()

                availableRuntimes = (await runtimeResponse ?? []).sorted { $0.id < $1.id }
                let newTasks = BackgroundTaskOrdering.newestFirst(await taskResponse ?? [])
                notifyCompletedTasks(old: tasks, new: newTasks)
                tasks = newTasks
                historySessions = HistorySessionMerge.merging(
                    server: await sessionResponse,
                    existing: historySessions,
                    activeSessionID: currentSessionID,
                    activeAgent: selectedAgent
                )

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
            // Real connection failures must remain visible. Preview agents can
            // otherwise make an unavailable Local service appear configured.
            if activeEnvironment == .local {
                localAgents = []
                agents = []
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
            addActiveSessionToHistory(session.sessionID, agent: session.agent)
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

    func sendChat(
        _ prompt: String,
        attachments: [ChatAttachment] = [],
        sessionKey: ChatTranscriptKey? = nil,
        isQueuedDispatch: Bool = false
    ) async -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return false }
        let streamEnvironment = sessionKey?.environmentValue ?? activeEnvironment
        let streamConfiguration = streamEnvironment == .local ? localConfiguration : remoteConfiguration
        let streamClient = client(for: streamEnvironment)

        if !isQueuedDispatch,
           sessionKey == nil,
           let currentSessionID {
            let key = ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID)
            if streamTranscripts.isStreaming(key)
                || queueDispatchingKeys.contains(key)
                || !queuedChatMessages.messages(for: key).isEmpty {
                enqueueChatMessage(QueuedChatMessage(text: trimmed, attachments: attachments), for: key)
                if !streamTranscripts.isStreaming(key), !queueDispatchingKeys.contains(key) {
                    scheduleNextQueuedMessage(for: key)
                }
                return true
            }
        }

        guard !streamConfiguration.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let message = "Authentication required. Add a bearer token in Settings, then click Save."
            if sessionKey.map(isViewingChat) ?? true {
                errorMessage = message
                chatMessages.append(ChatMessage(role: .system, text: message))
            }
            return false
        }

        let userMessage = ChatMessage(role: .user, text: trimmed, attachments: attachments)
        var sourceMessages = sessionKey.map { streamTranscripts.messages(for: $0, serverMessages: []) } ?? chatMessages
        sourceMessages.append(userMessage)
        if sessionKey.map(isViewingChat) ?? true {
            chatMessages = sourceMessages
        }
        // Capture the source transcript before an await point. Navigation can
        // replace `chatMessages`, but this is the transcript the stream owns.
        isLoading = true
        errorMessage = nil
        var sourceTranscriptKey: ChatTranscriptKey?
        var activeStreamKey: ChatTranscriptKey?
        var activeStreamMessageID: UUID?
        defer {
            if let activeStreamKey {
                streamTranscripts.finishStream(for: activeStreamKey)
                markStreamingChanged()
            }
            isLoading = false
        }

        do {
            let sessionID: String
            if let sessionKey {
                sessionID = sessionKey.sessionID
            } else if let currentSessionID {
                sessionID = currentSessionID
            } else {
                let desiredAgent = selectedAgent
                let desiredRuntime = selectedRuntimeOrNil
                let desiredModel = selectedModelOrNil
                let session = try await streamClient.createSession(agent: nil, model: nil, runtime: nil)
                currentSessionID = session.sessionID
                addActiveSessionToHistory(session.sessionID, agent: session.agent)
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

            let transcriptKey = ChatTranscriptKey(environment: streamEnvironment, sessionID: sessionID)
            sourceTranscriptKey = transcriptKey
            streamTranscripts.retainTranscript(for: transcriptKey, messages: sourceMessages)

            for attachment in attachments {
                _ = try await streamClient.uploadFile(
                    sessionID: sessionID,
                    data: attachment.data,
                    filename: attachment.filename,
                    mimeType: attachment.mimeType
                )
            }

            let query = attachments.isEmpty ? trimmed : (trimmed.isEmpty ? "[Attached \(attachments.count) file(s)]" : trimmed)
            let streamKey = transcriptKey
            activeStreamKey = streamKey

            // A stream can outlive the visible chat or selected session. Keep
            // the entire source transcript by identity rather than relying on
            // the visible `chatMessages` array.
            let streamMessage = ChatMessage(role: .assistant, text: "")
            let streamMessageID = streamMessage.id
            activeStreamMessageID = streamMessageID
            var streamingMessages = sourceMessages
            streamingMessages.append(streamMessage)
            streamTranscripts.beginStream(for: streamKey, messages: streamingMessages)
            markStreamingChanged()
            if isViewingChat(streamKey) {
                chatMessages = streamingMessages
            }

            let bytes = try await streamClient.stream(
                sessionID: sessionID,
                query: query,
                agent: nil,
                runtime: nil,
                model: nil
            )

            var rawStreamText = ""
            var lastActivityText = ""
            var streamReportedError = false
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
                            updateStreamTranscript(streamKey, messageID: streamMessageID) { message in
                                message.text = cleaned
                            }
                        }
                    }
                case "tool_call":
                    lastActivityText = streamActivityText(from: event)
                    if let message = streamTranscripts.messages(for: streamKey, serverMessages: [] as [ChatMessage]).first(where: { $0.id == streamMessageID }),
                       message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       !lastActivityText.isEmpty {
                        updateStreamTranscript(streamKey, messageID: streamMessageID) { message in
                            message.text = lastActivityText
                        }
                    }
                case "done":
                    let finalText = preferredFinalStreamText(accumulated: rawStreamText, doneResponse: event.response)
                    if let message = streamTranscripts.messages(for: streamKey, serverMessages: [] as [ChatMessage]).first(where: { $0.id == streamMessageID }) {
                        if !finalText.isEmpty {
                            updateStreamTranscript(streamKey, messageID: streamMessageID) { message in
                                message.text = finalText
                            }
                        } else if message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  !lastActivityText.isEmpty {
                            updateStreamTranscript(streamKey, messageID: streamMessageID) { message in
                                message.text = lastActivityText
                            }
                        }
                    }
                    // Do not let a Local stream overwrite the current Remote
                    // environment's model/runtime after navigation.
                    if isViewingChat(streamKey),
                       let runtime = event.runtime, !runtime.isEmpty {
                        selectedRuntime = runtime
                    }
                    if isViewingChat(streamKey),
                       let model = event.model, !model.isEmpty {
                        selectedModel = model
                    }
                case "error":
                    streamReportedError = true
                    let message = event.message ?? event.text ?? "Stream error"
                    updateStreamTranscript(streamKey, messageID: streamMessageID) { streamMessage in
                        streamMessage.text = message
                    }
                default:
                    break
                }
            }

            if let message = streamTranscripts.messages(for: streamKey, serverMessages: [] as [ChatMessage]).first(where: { $0.id == streamMessageID }),
               message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let finalText = preferredFinalStreamText(accumulated: rawStreamText, doneResponse: nil)
                if !finalText.isEmpty {
                    updateStreamTranscript(streamKey, messageID: streamMessageID) { message in
                        message.text = finalText
                    }
                } else if !lastActivityText.isEmpty {
                    updateStreamTranscript(streamKey, messageID: streamMessageID) { message in
                        message.text = lastActivityText
                    }
                } else if cancellationRequestedKeys.contains(streamKey) {
                    updateStreamTranscript(streamKey, messageID: streamMessageID) { streamMessage in
                        streamMessage.text = "Request cancelled."
                    }
                } else {
                    // A well-formed stream always provides text, activity, a
                    // done event, or an error. Keep this message visible when
                    // a runtime closes the stream without any of those signals
                    // so the user can see and report the actual failure.
                    let message = "The runtime ended without returning a response. Check the Local API service output, then retry."
                    updateStreamTranscript(streamKey, messageID: streamMessageID) { streamMessage in
                        streamMessage.text = message
                    }
                    if isViewingChat(streamKey) {
                        errorMessage = message
                    }
                }
            }

            streamTranscripts.finishStream(for: streamKey)
            let wasCancelled = cancellationRequestedKeys.remove(streamKey) != nil
            if isViewingChat(streamKey) {
                saveConfiguration()
                await loadHistorySessions()
            }
            if !streamReportedError, !wasCancelled, !isQueuedDispatch {
                scheduleNextQueuedMessage(for: streamKey)
            }
            return !streamReportedError && !wasCancelled
        } catch {
            let wasCancelled = activeStreamKey.map { cancellationRequestedKeys.remove($0) != nil } ?? false
            let message = wasCancelled ? "Request cancelled." : (handleAuthErrorIfNeeded(error) ?? error.localizedDescription)
            if let activeStreamKey, let activeStreamMessageID {
                updateStreamTranscript(activeStreamKey, messageID: activeStreamMessageID) { streamMessage in
                    streamMessage.text = message
                }
                if isViewingChat(activeStreamKey) {
                    errorMessage = message
                }
            } else if let sourceTranscriptKey {
                var errorMessageTranscript = streamTranscripts.messages(for: sourceTranscriptKey, serverMessages: [])
                errorMessageTranscript.append(ChatMessage(role: .system, text: message))
                streamTranscripts.retainTranscript(for: sourceTranscriptKey, messages: errorMessageTranscript)
                if isViewingChat(sourceTranscriptKey) {
                    errorMessage = message
                    chatMessages = errorMessageTranscript
                }
            } else if activeEnvironment == streamEnvironment {
                errorMessage = message
                chatMessages.append(ChatMessage(role: .system, text: message))
            }
            return false
        }
    }

    func cancelCurrentChatRequest() async {
        guard let currentSessionID else {
            errorMessage = "No running request to cancel."
            return
        }

        let key = ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID)
        guard streamTranscripts.isStreaming(key) else {
            let message = "No running request to cancel."
            errorMessage = message
            chatMessages.append(ChatMessage(role: .system, text: message))
            return
        }

        appendToStreamTranscript(ChatMessage(role: .user, text: "/cancel"), for: key)
        cancellationRequestedKeys.insert(key)
        do {
            let response = try await client(for: activeEnvironment).cancelSession(sessionID: currentSessionID)
            let status = response.cancelled ? "✓ \(response.message)" : "ℹ️ \(response.message)"
            appendToStreamTranscript(ChatMessage(role: .system, text: status), for: key)
            guard response.cancelled else {
                cancellationRequestedKeys.remove(key)
                errorMessage = status
                return
            }

            if isViewingChat(key) {
                errorMessage = nil
            }
        } catch {
            cancellationRequestedKeys.remove(key)
            let message = handleAuthErrorIfNeeded(error) ?? error.localizedDescription
            if isViewingChat(key) {
                errorMessage = message
            }
            appendToStreamTranscript(ChatMessage(role: .system, text: "❌ Failed to cancel: \(message)"), for: key)
        }
    }

    private func isViewingChat(_ key: ChatTranscriptKey) -> Bool {
        key.environment == activeEnvironment.rawValue && key.sessionID == currentSessionID
    }

    private func updateStreamTranscript(
        _ key: ChatTranscriptKey,
        messageID: UUID,
        update: (inout ChatMessage) -> Void
    ) {
        streamTranscripts.updateMessage(id: messageID, for: key, update: update)
        if isViewingChat(key) {
            chatMessages = streamTranscripts.messages(for: key, serverMessages: [])
        }
    }

    private func appendToStreamTranscript(_ message: ChatMessage, for key: ChatTranscriptKey) {
        var messages = streamTranscripts.messages(for: key, serverMessages: [])
        messages.append(message)
        streamTranscripts.retainTranscript(for: key, messages: messages)
        if isViewingChat(key) {
            chatMessages = messages
        }
    }

    func toggleChatQueuePause() {
        isChatQueuePaused.toggle()
        guard !isChatQueuePaused, let currentSessionID else { return }
        let key = ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID)
        if !streamTranscripts.isStreaming(key) {
            scheduleNextQueuedMessage(for: key)
        }
    }

    func removeQueuedChatMessage(id: UUID) {
        guard let currentSessionID else { return }
        let key = ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID)
        if queuedChatMessages.remove(id: id, for: key) != nil {
            markChatQueueChanged()
        }
    }

    func takeQueuedChatMessageForEditing(id: UUID) -> QueuedChatMessage? {
        guard let currentSessionID else { return nil }
        let key = ChatTranscriptKey(environment: activeEnvironment, sessionID: currentSessionID)
        let message = queuedChatMessages.remove(id: id, for: key)
        if message != nil {
            markChatQueueChanged()
        }
        return message
    }

    private func scheduleNextQueuedMessage(for key: ChatTranscriptKey) {
        guard !isChatQueuePaused,
              !streamTranscripts.isStreaming(key),
              !queueDispatchingKeys.contains(key),
              !queuedChatMessages.messages(for: key).isEmpty else { return }
        queueDispatchingKeys.insert(key)
        Task { @MainActor [weak self] in
            await self?.dispatchNextQueuedMessage(for: key)
        }
    }

    private func dispatchNextQueuedMessage(for key: ChatTranscriptKey) async {
        guard !isChatQueuePaused,
              !streamTranscripts.isStreaming(key),
              let next = queuedChatMessages.takeNext(for: key) else {
            queueDispatchingKeys.remove(key)
            return
        }
        markChatQueueChanged()
        let succeeded = await sendChat(next.text, attachments: next.attachments, sessionKey: key, isQueuedDispatch: true)
        queueDispatchingKeys.remove(key)
        if succeeded {
            scheduleNextQueuedMessage(for: key)
        }
    }

    private func markChatQueueChanged() {
        chatQueueRevision &+= 1
    }

    /// Enqueues a chat message and bumps the observation revision so the
    /// queue panel refreshes. Internal (not private) so tests can seed the
    /// queue directly without driving a full network stream.
    func enqueueChatMessage(_ message: QueuedChatMessage, for key: ChatTranscriptKey) {
        queuedChatMessages.enqueue(message, for: key)
        markChatQueueChanged()
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
            addActiveSessionToHistory(session.sessionID, agent: session.agent)
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
            chatHistoryTotal = 0
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

        let server = try? await client.historySessions()
        historySessions = HistorySessionMerge.merging(
            server: server,
            existing: historySessions,
            activeSessionID: currentSessionID,
            activeAgent: selectedAgent
        )
    }

    /// The API persists a newly created session immediately, but a streaming
    /// response may take a while to finish. Show that session in Recent Chats
    /// right away rather than making the sidebar look empty during the stream.
    private func addActiveSessionToHistory(_ sessionID: String, agent: String?) {
        guard !historySessions.contains(where: { $0.sessionID == sessionID }) else { return }
        let now = Date().timeIntervalSince1970
        let resolvedAgent = (agent ?? selectedAgent).trimmingCharacters(in: .whitespacesAndNewlines)
        let session = HistorySessionSummary(
            sessionID: sessionID,
            title: nil,
            preview: nil,
            agent: resolvedAgent.isEmpty ? nil : resolvedAgent,
            createdAt: now,
            updatedAt: now
        )
        historySessions.insert(session, at: 0)
    }

    func selectHistorySession(_ session: HistorySessionSummary) async {
        guard hasAuthToken else { return }

        let transcriptKey = ChatTranscriptKey(environment: activeEnvironment, sessionID: session.sessionID)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Do not replace an in-flight transcript with the API's older
            // persisted history. Its stream continues in the model even when
            // the user navigates to another view or thread.
            if streamTranscripts.isStreaming(transcriptKey) {
                currentSessionID = session.sessionID
                if let agent = session.agent, !agent.isEmpty {
                    selectedAgent = agent
                    saveConfiguration()
                }
                chatMessages = streamTranscripts.messages(for: transcriptKey, serverMessages: [])
                return
            }

            let response = try await client.historyMessages(
                sessionID: session.sessionID,
                limit: ChatStreamTranscriptStore.maximumMessages
            )
            currentSessionID = session.sessionID
            if let agent = session.agent, !agent.isEmpty {
                selectedAgent = agent
                saveConfiguration()
            }
            let serverMessages = response.messages.map(ChatMessage.init(historyMessage:))
            chatMessages = streamTranscripts.messages(for: transcriptKey, serverMessages: serverMessages)
            chatHistoryTotal = response.total ?? serverMessages.count
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
            chatMessages.append(ChatMessage(
                role: .system,
                text: response.response,
                isContextBoundary: SessionResetDetector.indicatesReset(response.response)
            ))
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
            tasks = BackgroundTaskOrdering.newestFirst(try await client.backgroundTasks())
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

    /// Issue #26.
    func deleteScheduledJob(id: String) async throws {
        try await client.deleteScheduledJob(id: id)
        await loadScheduledJobs()
        schedulerStatusMessage = "Scheduled task deleted."
    }

    func loadKanbanBoard() async {
        guard kanbanEnabled else {
            kanbanBoard = nil
            kanbanStatusMessage = nil
            return
        }
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
            sessionContextUsage = status.contextUsage
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
            chatMessages.append(ChatMessage(
                role: .system,
                text: response.response,
                isContextBoundary: SessionResetDetector.indicatesReset(response.response)
            ))
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
        let account = activeEnvironment == .local ? "api-token-local" : "api-token-remote"
        KeychainStore.saveSecret("", account: account)
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

        switch event.status ?? event.event {
        case "running", "detected":
            return "Running \(label)..."
        case "complete", "completed":
            if event.isError == true,
               let output = (event.result ?? event.output)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                return "\(label) failed: \(output)"
            }
            if label == "search",
               let result = event.result?.trimmingCharacters(in: .whitespacesAndNewlines),
               !result.isEmpty {
                return "Search completed. Preparing answer…\n\n\(result)"
            }
            return "Ran \(label). Preparing answer…"
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

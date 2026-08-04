import Darwin
import SwiftUI

// MARK: - PTY process

enum PTYError: LocalizedError {
    case forkFailed

    var errorDescription: String? {
        switch self {
        case .forkFailed: "Could not start a shell (fork failed)."
        }
    }
}

/// A real PTY-backed shell process, owned by one `ShellSessionController`.
///
/// Uses `forkpty` directly rather than `Foundation.Process`: `Process` spawns via
/// `posix_spawn`, which has no way to make the child a session leader with the
/// PTY as its controlling terminal, so job control (Ctrl-C interrupting a
/// running command, Ctrl-Z suspending it) would not work. `forkpty` does that
/// as part of the fork itself. Everything the child needs (argv, envp) is built
/// as plain C arrays *before* forking, so the child -- which must not touch the
/// Swift runtime or call anything that allocates, since another thread may hold
/// the malloc lock at the moment of fork -- only ever calls `execve` and `_exit`,
/// both async-signal-safe.
final class PTYProcess {
    private(set) var masterFD: Int32 = -1
    private(set) var childPID: pid_t = -1
    private(set) var isRunning = false

    /// Rendered scrollback. Not true terminal emulation (see `ingest`) --
    /// a v1 scoping call, not an oversight: full-screen apps (vim, top, less)
    /// will not render correctly, but ordinary command output does.
    private(set) var lines: [String] = [""]
    /// Monotonic count of logical characters ever appended, never decremented by
    /// scrollback trimming, so a mark taken before trimming can still be diffed
    /// against (falling back to "everything still retained" if the gap exceeds
    /// what's left).
    private(set) var totalEmittedCount = 0

    private static let maxScrollbackLines = 4000

    var onOutputAppended: (() -> Void)?
    var onExited: (() -> Void)?

    private var readSource: DispatchSourceRead?
    private var pendingEscape = ""
    private var cursorColumn = 0

    var displayText: String { lines.joined(separator: "\n") }

    func start(shellPath: String = "/bin/zsh", args: [String] = ["-il"]) throws {
        guard !isRunning else { return }

        var winSize = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        var master: Int32 = 0

        let argv: [UnsafeMutablePointer<CChar>?] = ([shellPath] + args).map { strdup($0) } + [nil]
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        let envp: [UnsafeMutablePointer<CChar>?] = env.map { strdup("\($0.key)=\($0.value)") } + [nil]

        let pid = forkpty(&master, nil, nil, &winSize)
        if pid == 0 {
            argv.withUnsafeBufferPointer { argvBuf in
                envp.withUnsafeBufferPointer { envpBuf in
                    execve(shellPath, argvBuf.baseAddress, envpBuf.baseAddress)
                }
            }
            _exit(127)
        }

        for pointer in argv where pointer != nil { free(pointer) }
        for pointer in envp where pointer != nil { free(pointer) }

        guard pid > 0 else { throw PTYError.forkFailed }

        masterFD = master
        childPID = pid
        isRunning = true
        startReading()
    }

    private func startReading() {
        let fd = masterFD
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.readAvailable(fd: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        readSource = source
    }

    private func readAvailable(fd: Int32) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &chunk, chunk.count)
        guard n > 0 else {
            DispatchQueue.main.async { [weak self] in self?.handleExit() }
            return
        }
        let text = String(decoding: chunk[0..<n], as: UTF8.self)
        DispatchQueue.main.async { [weak self] in self?.ingest(text) }
    }

    private func handleExit() {
        guard isRunning else { return }
        isRunning = false
        var status: Int32 = 0
        waitpid(childPID, &status, 0)
        readSource?.cancel()
        readSource = nil
        onExited?()
    }

    /// Applies just enough control-character handling to be readable: newline
    /// starts a fresh line, carriage return goes back to the start of the
    /// current line via a one-dimensional cursor column (overwrite at that
    /// column, matching CR-then-redraw output like progress bars and zle's
    /// own line echo), interprets CSI erase-in-line (`\x1B[K`/`0K`/`1K`/`2K`,
    /// which a real prompt uses to clean up after itself), and strips every
    /// other ANSI escape sequence (color, cursor movement, OSC title/shell
    /// integration markers) rather than acting on it. That stops short of
    /// two-dimensional cursor addressing or an alternate screen buffer, so
    /// full-screen apps (vim, top, less) will not render correctly -- a v1
    /// scoping call, not an oversight.
    private func ingest(_ text: String) {
        // Operates on unicode scalars, not `Character`s: Swift's `Character`
        // is an extended grapheme cluster, and CR+LF -- the two-byte newline
        // every one of these tools actually sends -- combine into a *single*
        // grapheme cluster that matches neither `case "\r"` nor `case "\n"`.
        // Scanning by `Character` silently ate every newline in real output;
        // scalars keep CR and LF distinct the way a terminal needs them to be.
        let combined = pendingEscape + text
        pendingEscape = ""
        let scalars = combined.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\u{1B}" {
                guard let (consumed, sequence) = Self.consumeEscapeSequence(in: scalars, from: index) else {
                    pendingEscape = String(String.UnicodeScalarView(scalars[index...]))
                    break
                }
                index = consumed
                applyEraseInLine(sequence)
                continue
            }
            switch scalar {
            case "\n":
                lines.append("")
                cursorColumn = 0
                totalEmittedCount += 1
            case "\r":
                cursorColumn = 0
                totalEmittedCount += 1
            case "\u{08}", "\u{7F}":
                cursorColumn = max(0, cursorColumn - 1)
                totalEmittedCount += 1
            case "\u{07}":
                break
            default:
                writeAtCursor(Character(scalar))
                totalEmittedCount += 1
            }
            index = scalars.index(after: index)
        }
        if lines.count > Self.maxScrollbackLines {
            lines.removeFirst(lines.count - Self.maxScrollbackLines)
        }
        onOutputAppended?()
    }

    /// Overwrites the character at `cursorColumn` on the current line (padding
    /// with spaces first if the cursor sits past the line's current end),
    /// then advances the cursor -- this is what makes CR-then-overwrite output
    /// (a shell prompt redraw, `\r`-based progress bars) render sensibly
    /// instead of destroying whatever was already on the line.
    private func writeAtCursor(_ char: Character) {
        var chars = Array(lines[lines.count - 1])
        while chars.count < cursorColumn { chars.append(" ") }
        if cursorColumn < chars.count {
            chars[cursorColumn] = char
        } else {
            chars.append(char)
        }
        lines[lines.count - 1] = String(chars)
        cursorColumn += 1
    }

    private func applyEraseInLine(_ sequence: String) {
        guard sequence.hasPrefix("\u{1B}["), sequence.hasSuffix("K") else { return }
        let param = sequence.dropFirst(2).dropLast()
        var chars = Array(lines[lines.count - 1])
        switch param {
        case "", "0":
            if cursorColumn < chars.count { chars.removeLast(chars.count - cursorColumn) }
        case "1":
            for i in 0..<min(cursorColumn, chars.count) { chars[i] = " " }
        case "2":
            chars = []
        default:
            return
        }
        lines[lines.count - 1] = String(chars)
    }

    /// Returns the index just past a complete escape sequence starting at
    /// `start` plus the sequence's own text, or nil if it runs off the end of
    /// the scalar view -- meaning the caller should hold what's left and
    /// retry once more bytes arrive.
    private static func consumeEscapeSequence(
        in scalars: String.UnicodeScalarView,
        from start: String.UnicodeScalarView.Index
    ) -> (String.UnicodeScalarView.Index, String)? {
        var index = scalars.index(after: start)
        guard index < scalars.endIndex else { return nil }
        let marker = scalars[index]
        if marker == "[" {
            index = scalars.index(after: index)
            while index < scalars.endIndex {
                let value = scalars[index].value
                if value >= 0x40, value <= 0x7E {
                    let end = scalars.index(after: index)
                    return (end, String(String.UnicodeScalarView(scalars[start..<end])))
                }
                index = scalars.index(after: index)
            }
            return nil
        } else if marker == "]" {
            index = scalars.index(after: index)
            while index < scalars.endIndex {
                if scalars[index] == "\u{07}" {
                    let end = scalars.index(after: index)
                    return (end, String(String.UnicodeScalarView(scalars[start..<end])))
                }
                if scalars[index] == "\u{1B}" {
                    let next = scalars.index(after: index)
                    if next < scalars.endIndex, scalars[next] == "\\" {
                        let end = scalars.index(after: next)
                        return (end, String(String.UnicodeScalarView(scalars[start..<end])))
                    }
                }
                index = scalars.index(after: index)
            }
            return nil
        } else {
            let end = scalars.index(after: index)
            return (end, String(String.UnicodeScalarView(scalars[start..<end])))
        }
    }

    func write(_ text: String) {
        guard masterFD >= 0 else { return }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            var written = 0
            while written < buffer.count {
                let n = Darwin.write(masterFD, buffer.baseAddress! + written, buffer.count - written)
                if n <= 0 { break }
                written += n
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        guard masterFD >= 0 else { return }
        var ws = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
    }

    /// Everything appended since `mark`, a previous `totalEmittedCount`
    /// snapshot. If scrollback trimming has since discarded part of that
    /// range, returns what's still retained rather than failing.
    func textSince(mark: Int) -> String {
        let emittedSinceMark = totalEmittedCount - mark
        guard emittedSinceMark > 0 else { return "" }
        let full = displayText
        guard emittedSinceMark <= full.count else { return full }
        return String(full.suffix(emittedSinceMark))
    }

    func terminate() {
        guard isRunning else { return }
        if childPID > 0 {
            kill(childPID, SIGHUP)
        }
        readSource?.cancel()
        readSource = nil
        isRunning = false
    }
}

// MARK: - Session-scoped native shell

@MainActor
@Observable
final class ShellSessionStore {
    /// Same reasoning as `BrowserSessionStore.maximumCachedSessions`: each
    /// cached controller owns a live PTY and child shell process, which is
    /// cheaper than a WKWebView but still a real OS process that should not
    /// accumulate for the lifetime of the app.
    static let maximumCachedSessions = 4

    private var controllers: [String: ShellSessionController] = [:]
    private var recency: [String] = []
    private(set) var activeSessionKey: String?

    func controller(
        environment: WeeEnvironment,
        sessionID: String,
        client: WeeAPIClient
    ) -> ShellSessionController {
        let key = "\(environment.rawValue):\(sessionID)"
        if let existing = controllers[key] {
            touch(key)
            return existing
        }
        let controller = ShellSessionController(sessionKey: key, sessionID: sessionID, client: client)
        controllers[key] = controller
        touch(key)
        evictLeastRecentlyUsedIfNeeded()
        return controller
    }

    private func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictLeastRecentlyUsedIfNeeded() {
        while recency.count > Self.maximumCachedSessions {
            guard let evictable = recency.first(where: { $0 != activeSessionKey }) else { return }
            recency.removeAll { $0 == evictable }
            controllers.removeValue(forKey: evictable)?.disconnect()
        }
    }

    var cachedControllerCount: Int { controllers.count }

    @discardableResult
    func activate(
        environment: WeeEnvironment,
        sessionID: String,
        client: WeeAPIClient
    ) -> ShellSessionController {
        let selected = controller(environment: environment, sessionID: sessionID, client: client)
        for (key, controller) in controllers where key != selected.sessionKey {
            controller.disconnect()
        }
        activeSessionKey = selected.sessionKey
        selected.connect()
        return selected
    }

    func deactivateAll() {
        for controller in controllers.values {
            controller.disconnect()
        }
        activeSessionKey = nil
    }

    var pollingControllerCount: Int {
        controllers.values.filter(\.isPolling).count
    }
}

@MainActor
@Observable
final class ShellSessionController {
    let sessionKey: String
    let sessionID: String
    let clientID = UUID().uuidString
    let pty = PTYProcess()
    var bridgeStatus = "Connecting…"
    var lastError: String?
    /// Bumped on every PTY output append. The view observes this, not
    /// `pty.displayText` directly, since `PTYProcess` itself isn't `@Observable`
    /// (its state is mutated from a background read queue, then hopped to main).
    var revision = 0

    private let client: WeeAPIClient
    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var llmReadMark = 0
    @ObservationIgnored private var started = false
    @ObservationIgnored private var terminalColumns = 0
    @ObservationIgnored private var terminalRows = 0

    init(sessionKey: String, sessionID: String, client: WeeAPIClient) {
        self.sessionKey = sessionKey
        self.sessionID = sessionID
        self.client = client
    }

    deinit {
        pollingTask?.cancel()
        pty.terminate()
    }

    var isPolling: Bool { pollingTask != nil }

    private func ensureStarted() {
        guard !started else { return }
        started = true
        pty.onOutputAppended = { [weak self] in
            self?.revision += 1
        }
        pty.onExited = { [weak self] in
            self?.lastError = "The shell exited."
        }
        do {
            try pty.start()
        } catch {
            lastError = "Could not start shell: \(error.localizedDescription)"
        }
    }

    func connect() {
        ensureStarted()
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollCommands()
        }
    }

    /// Stops this session's command poller and releases its long-poll
    /// connection. The PTY itself keeps running -- disconnecting just means
    /// the LLM stops being able to reach it while this session isn't active,
    /// the same as leaving a background shell tab open.
    func disconnect() {
        guard let pollingTask else { return }
        pollingTask.cancel()
        self.pollingTask = nil
        bridgeStatus = "Paused"
    }

    /// The user typed this directly into the panel. It goes through the exact
    /// same PTY the LLM's `run` action writes to, so both sides share one
    /// buffer -- there is no separate "user shell" and "agent shell".
    func submitUserInput(_ text: String) {
        ensureStarted()
        pty.write(text + "\n")
    }

    /// Keeps the PTY's logical terminal size in step with the resizable shell
    /// pane. Programs that use `$COLUMNS`, `$LINES`, or react to SIGWINCH now
    /// see the same dimensions as the panel the user is looking at.
    func resizeViewport(_ size: CGSize) {
        let columns = max(1, Int(size.width / 8))
        let rows = max(1, Int(size.height / 16))
        guard columns != terminalColumns || rows != terminalRows else { return }
        terminalColumns = columns
        terminalRows = rows
        pty.resize(cols: columns, rows: rows)
    }

    private func pollCommands() async {
        do {
            try await client.registerNativeShell(sessionID: sessionID, clientID: clientID)
            bridgeStatus = "Wee connected"
        } catch {
            bridgeStatus = Self.bridgeStatus(for: error)
            lastError = bridgeStatus == "Reconnecting…" ? error.localizedDescription : nil
        }

        while !Task.isCancelled {
            do {
                let envelope = try await client.pollNativeShellCommand(
                    sessionID: sessionID,
                    clientID: clientID
                )
                bridgeStatus = "Wee connected"
                guard let command = envelope.command else { continue }
                let result = await execute(command)
                try await client.submitNativeShellResult(
                    sessionID: sessionID,
                    result: ShellCommandResultRequest(
                        clientID: clientID,
                        commandID: command.id,
                        output: result.value,
                        error: result.error
                    )
                )
            } catch is CancellationError {
                break
            } catch {
                if Task.isCancelled { break }
                bridgeStatus = Self.bridgeStatus(for: error)
                lastError = bridgeStatus == "Reconnecting…" ? error.localizedDescription : nil
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                try? await client.registerNativeShell(sessionID: sessionID, clientID: clientID)
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

    private func execute(_ command: ShellCommand) async -> (value: String?, error: String?) {
        ensureStarted()
        guard pty.isRunning else {
            return (nil, "The shell process is not running.")
        }
        let action = command.action.lowercased()
        switch action {
        case "run":
            guard let line = command.command, !line.isEmpty else {
                return (nil, "run requires command")
            }
            pty.write(line + "\n")
        case "write":
            guard let text = command.text, !text.isEmpty else {
                return (nil, "write requires text")
            }
            pty.write(text)
        case "key":
            guard let key = command.key, let bytes = Self.keyBytes(key) else {
                return (nil, "key requires a recognized key name")
            }
            pty.write(bytes)
        case "read":
            break
        default:
            return (nil, "Unknown shell action: \(command.action)")
        }
        if action != "read" {
            await waitForQuiet()
        }
        let output = pty.textSince(mark: llmReadMark)
        llmReadMark = pty.totalEmittedCount
        return (output.isEmpty ? "(no new output)" : output, nil)
    }

    /// Command output can trickle in over several PTY reads; returning after
    /// the first one would cut it off mid-line. Waits for a short quiet period
    /// with no new output, up to a hard cap so a long-running command (a dev
    /// server, a watch task) doesn't block the tool call forever -- the agent
    /// can always follow up with `shell_read` to see what came in since.
    private func waitForQuiet() async {
        var lastCount = pty.totalEmittedCount
        var stableTicks = 0
        for tick in 0..<80 {
            try? await Task.sleep(for: .milliseconds(100))
            let current = pty.totalEmittedCount
            if current != lastCount {
                lastCount = current
                stableTicks = 0
            } else {
                stableTicks += 1
                // Requiring a few ticks up front before the stability check can
                // fire at all guards against a command that hasn't started
                // producing output yet in the first ~100-200ms (fork+exec/dotfile
                // overhead), which would otherwise read as "already quiet" and
                // return before anything of the command's own ran.
                if tick >= 2, stableTicks >= 4 { break }
            }
        }
    }

    private static func keyBytes(_ name: String) -> String? {
        switch name.lowercased() {
        case "ctrl-c": "\u{03}"
        case "ctrl-d": "\u{04}"
        case "tab": "\t"
        case "up": "\u{1B}[A"
        case "down": "\u{1B}[B"
        case "right": "\u{1B}[C"
        case "left": "\u{1B}[D"
        case "enter": "\r"
        case "escape": "\u{1B}"
        case "backspace": "\u{7F}"
        default: nil
        }
    }
}

struct NativeShellPanel: View {
    @Bindable var controller: ShellSessionController
    @Binding var isVisible: Bool
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "terminal")
                Text("Shell")
                    .weeFont(.subheadline, weight: .semibold)
                Spacer()
                Button { isVisible = false } label: { Image(systemName: "sidebar.trailing") }
                    .help("Hide shell")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(WeeTheme.textSecondary)
            .padding(8)
            .background(WeeTheme.sidebar)

            HStack {
                Image(systemName: "circle.fill")
                    .weeFont(size: 6)
                    .foregroundStyle(controller.bridgeStatus == "Wee connected" ? WeeTheme.emerald : WeeTheme.gold)
                Text(controller.pty.isRunning ? "zsh" : "not running")
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

            ScrollViewReader { proxy in
                ScrollView {
                    Text(controller.pty.displayText.isEmpty ? " " : controller.pty.displayText)
                        .weeFont(.caption, design: .monospaced)
                        .foregroundStyle(Color.white.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("shell-bottom-\(controller.sessionKey)")
                }
                .background(Color.black.opacity(0.85))
                .onChange(of: controller.revision) {
                    proxy.scrollTo("shell-bottom-\(controller.sessionKey)", anchor: .bottom)
                }
            }
            .background(ShellViewportReporter { controller.resizeViewport($0) })
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

            HStack(spacing: 8) {
                Text("$")
                    .weeFont(.caption, design: .monospaced)
                    .foregroundStyle(WeeTheme.textMuted)
                TextField("Type a command", text: $inputText)
                    .textFieldStyle(.plain)
                    .weeFont(.caption, design: .monospaced)
                    .focused($inputFocused)
                    .onSubmit {
                        let command = inputText
                        inputText = ""
                        guard !command.isEmpty else { return }
                        controller.submitUserInput(command)
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(WeeTheme.surfaceRaised)
            .overlay(alignment: .top) { Rectangle().fill(WeeTheme.divider).frame(height: 1) }
        }
        .background(WeeTheme.background)
        .onAppear {
            controller.connect()
            reclaimFocus()
        }
    }

    /// AppKit can leave another view (typically the browser's `WKWebView`) as first
    /// responder for one or more run-loop turns after this panel is inserted into the
    /// split view — a single reclaim attempt on appear is not reliable, and was
    /// observed to fail specifically when this panel is created for the first time by
    /// sending the first message in a brand-new chat. Retry across a few turns so the
    /// TextField wins first responder once the view hierarchy has actually settled.
    private func reclaimFocus() {
        for delay in [0, 30, 120, 300] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                inputFocused = true
            }
        }
    }
}

/// Reports the scrollable terminal surface's actual AppKit-backed size without
/// influencing the surrounding split view's layout.
private struct ShellViewportReporter: View {
    let onResize: (CGSize) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { onResize(proxy.size) }
                .onChange(of: proxy.size) { _, size in onResize(size) }
        }
    }
}

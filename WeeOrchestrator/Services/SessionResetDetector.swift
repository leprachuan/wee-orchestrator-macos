import Foundation

/// Detects whether a session-configuration command response (e.g. from
/// `/session reset`) indicates the backend wiped the session's conversation
/// context. Runtime switches are excluded because the API hands conversation
/// context into the new runtime.
///
/// A real manual reset explicitly says that the next message starts fresh.
/// Pulled out as pure logic (mirrors `HistorySessionMerge`) so it's unit
/// testable without the app's actor-isolated network/session state.
enum SessionResetDetector {
    static func indicatesReset(_ responseText: String) -> Bool {
        responseText.range(
            of: "session reset. next message starts fresh",
            options: [.caseInsensitive]
        ) != nil
    }
}

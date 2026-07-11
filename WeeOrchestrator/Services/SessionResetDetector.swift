import Foundation

/// Detects whether a session-configuration command response (e.g. from
/// `/runtime set`, `/model set`, `/agent set`) indicates the backend wiped
/// the session's conversation context.
///
/// Issue #399: switching runtime/model/agent mid-chat resets the backend
/// session, but the macOS client kept appending to the same local
/// `chatMessages` array with no visual distinction, so a follow-up question
/// referencing earlier turns silently lost all context. Pulled out as pure
/// logic (mirrors `HistorySessionMerge`) so it's unit testable without the
/// app's actor-isolated network/session state.
enum SessionResetDetector {
    static func indicatesReset(_ responseText: String) -> Bool {
        responseText.range(of: "session reset", options: [.caseInsensitive]) != nil
    }
}

import Foundation

/// Pure merge logic for Recent Chats, split out of `WeeAppModel` so it can be
/// unit tested without the app's actor-isolated network/session state.
enum HistorySessionMerge {
    /// Combines a history fetch result with whatever the sidebar already
    /// shows, guaranteeing the active session is never dropped.
    ///
    /// Two failure modes this guards against (see issue #388):
    /// - The history fetch throws (`server == nil`, e.g. a Local API that
    ///   isn't fully warmed up yet) -- previously this wiped `historySessions`
    ///   to `[]`, hiding an active session that had already been shown
    ///   optimistically.
    /// - The fetch succeeds but the server hasn't persisted the just-created
    ///   session yet -- the active session is re-inserted so it doesn't
    ///   flicker out of the list.
    static func merging(
        server: [HistorySessionSummary]?,
        existing: [HistorySessionSummary],
        activeSessionID: String?,
        activeAgent: String?
    ) -> [HistorySessionSummary] {
        guard let server else {
            return existing
        }

        guard let activeSessionID, !activeSessionID.isEmpty,
              !server.contains(where: { $0.sessionID == activeSessionID }) else {
            return server
        }

        if let optimistic = existing.first(where: { $0.sessionID == activeSessionID }) {
            return [optimistic] + server
        }

        let resolvedAgent = activeAgent?.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date().timeIntervalSince1970
        let optimistic = HistorySessionSummary(
            sessionID: activeSessionID,
            title: nil,
            preview: nil,
            agent: (resolvedAgent?.isEmpty ?? true) ? nil : resolvedAgent,
            createdAt: now,
            updatedAt: now
        )
        return [optimistic] + server
    }
}

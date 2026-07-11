import XCTest
@testable import WeeOrchestrator

final class HistorySessionMergeTests: XCTestCase {
    private func makeSummary(_ id: String) -> HistorySessionSummary {
        HistorySessionSummary(
            sessionID: id,
            title: "Session \(id)",
            preview: nil,
            agent: "orchestrator",
            createdAt: 1,
            updatedAt: 1
        )
    }

    /// Issue #388: a freshly created Local session was optimistically shown in
    /// Recent Chats, but the subsequent history refresh threw (e.g. the Local
    /// API wasn't fully warmed up yet) and the sidebar was reset to empty,
    /// hiding the active session entirely.
    func test_issue_388_activeSessionSurvivesFailedHistoryFetch() {
        let optimistic = makeSummary("active-session")
        let merged = HistorySessionMerge.merging(
            server: nil,
            existing: [optimistic],
            activeSessionID: "active-session",
            activeAgent: "orchestrator"
        )

        XCTAssertEqual(merged.map(\.sessionID), ["active-session"])
    }

    func test_issue_388_activeSessionReinsertedWhenServerHasNotPersistedItYet() {
        let optimistic = makeSummary("active-session")
        let serverOnly = [makeSummary("older-session")]

        let merged = HistorySessionMerge.merging(
            server: serverOnly,
            existing: [optimistic],
            activeSessionID: "active-session",
            activeAgent: "orchestrator"
        )

        XCTAssertEqual(merged.map(\.sessionID), ["active-session", "older-session"])
    }

    func test_serverListUsedDirectlyWhenActiveSessionAlreadyPresent() {
        let server = [makeSummary("active-session"), makeSummary("older-session")]

        let merged = HistorySessionMerge.merging(
            server: server,
            existing: [],
            activeSessionID: "active-session",
            activeAgent: "orchestrator"
        )

        XCTAssertEqual(merged.map(\.sessionID), ["active-session", "older-session"])
    }

    func test_serverListUsedDirectlyWhenNoActiveSession() {
        let server = [makeSummary("older-session")]

        let merged = HistorySessionMerge.merging(
            server: server,
            existing: [],
            activeSessionID: nil,
            activeAgent: nil
        )

        XCTAssertEqual(merged.map(\.sessionID), ["older-session"])
    }
}

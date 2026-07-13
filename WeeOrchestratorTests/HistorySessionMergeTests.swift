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

    /// Issue #11: selecting another app section or chat replaced the one
    /// visible transcript while a stream was active, so future stream chunks
    /// could not be rendered when returning to their source session.
    func test_issue_11_activeStreamTranscriptSurvivesNavigationAwayAndBack() {
        let key = ChatTranscriptKey(environment: .local, sessionID: "streaming-session")
        let user = ChatMessage(role: .user, text: "Look this up")
        let assistant = ChatMessage(role: .assistant, text: "")
        var store = ChatStreamTranscriptStore()

        store.beginStream(for: key, messages: [user, assistant])
        store.updateMessage(id: assistant.id, for: key) { message in
            message.text = "The stream completed while another view was open."
        }

        // Simulate selecting another thread: the visible transcript is now
        // unrelated, but the source session must still restore its live text.
        let otherThread = [ChatMessage(role: .system, text: "Another chat")]
        XCTAssertEqual(otherThread.first?.text, "Another chat")
        XCTAssertTrue(store.isStreaming(key))

        let restored = store.messages(for: key, serverMessages: [])
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.last?.text, "The stream completed while another view was open.")
    }

    func test_issue_11_cachedTranscriptWinsUntilServerHistoryCatchesUp() {
        let key = ChatTranscriptKey(environment: .remote, sessionID: "streaming-session")
        let user = ChatMessage(role: .user, text: "Question")
        let assistant = ChatMessage(role: .assistant, text: "Partial answer")
        var store = ChatStreamTranscriptStore()
        store.beginStream(for: key, messages: [user, assistant])

        XCTAssertEqual(store.messages(for: key, serverMessages: [user]).last?.text, "Partial answer")

        store.finishStream(for: key)
        let serverAnswer = ChatMessage(role: .assistant, text: "Final answer")
        XCTAssertEqual(store.messages(for: key, serverMessages: [user, serverAnswer]).last?.text, "Final answer")
    }
}

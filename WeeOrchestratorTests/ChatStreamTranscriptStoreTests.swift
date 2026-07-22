import XCTest
@testable import WeeOrchestrator

final class ChatStreamTranscriptStoreTests: XCTestCase {
    /// Backs both `isCurrentSessionStreaming` and `isSessionStreaming(_:)`
    /// (used by the recent-chats rail streaming indicator). A session must
    /// only report as streaming between `beginStream` and `finishStream` for
    /// its own key, and must not leak into other sessions/environments.
    func test_streamingStateIsScopedToItsOwnSessionKey() {
        var store = ChatStreamTranscriptStore()
        let activeKey = ChatTranscriptKey(environment: .remote, sessionID: "session-a")
        let otherSessionKey = ChatTranscriptKey(environment: .remote, sessionID: "session-b")
        let otherEnvironmentKey = ChatTranscriptKey(environment: .local, sessionID: "session-a")

        XCTAssertFalse(store.isStreaming(activeKey))

        store.beginStream(for: activeKey, messages: [])
        XCTAssertTrue(store.isStreaming(activeKey))
        XCTAssertFalse(store.isStreaming(otherSessionKey))
        XCTAssertFalse(store.isStreaming(otherEnvironmentKey))

        store.finishStream(for: activeKey)
        XCTAssertFalse(store.isStreaming(activeKey))
    }

    func test_transcriptCacheKeepsOnlyTheMostRecentMessages() {
        var store = ChatStreamTranscriptStore()
        let key = ChatTranscriptKey(environment: .local, sessionID: "long-session")
        let messages = (0...ChatStreamTranscriptStore.maximumMessages).map {
            ChatMessage(role: .user, text: "message-\($0)")
        }

        store.beginStream(for: key, messages: messages)
        let cached = store.messages(for: key, serverMessages: [])

        XCTAssertEqual(cached.count, ChatStreamTranscriptStore.maximumMessages)
        XCTAssertEqual(cached.first?.text, "message-1")
        XCTAssertEqual(cached.last?.text, "message-\(ChatStreamTranscriptStore.maximumMessages)")
    }
}

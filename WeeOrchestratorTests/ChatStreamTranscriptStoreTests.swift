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

    func test_completedTranscriptCanBeRestoredFromCache() {
        var store = ChatStreamTranscriptStore()
        let key = ChatTranscriptKey(environment: .remote, sessionID: "completed-session")
        let messages = [ChatMessage(role: .user, text: "Question"), ChatMessage(role: .assistant, text: "Answer")]

        store.retainTranscript(for: key, messages: messages)

        XCTAssertEqual(store.cachedMessages(for: key)?.map(\.text), ["Question", "Answer"])
    }

    func test_cacheEvictsLeastRecentlyUsedCompletedSession() {
        var store = ChatStreamTranscriptStore()
        let keys = (0...ChatStreamTranscriptStore.maximumCachedSessions).map {
            ChatTranscriptKey(environment: .local, sessionID: "session-\($0)")
        }

        for key in keys {
            store.retainTranscript(for: key, messages: [ChatMessage(role: .user, text: key.sessionID)])
        }

        XCTAssertNil(store.cachedMessages(for: keys[0]))
        XCTAssertEqual(store.cachedMessages(for: keys.last!)?.first?.text, "session-\(ChatStreamTranscriptStore.maximumCachedSessions)")
    }

    func test_streamEventReadsNestedToolPayloads() throws {
        let data = """
        {
          "type": "tool_call",
          "status": "running",
          "data": {
            "tool_name": "shell",
            "arguments": { "command": "vm_stat" },
            "result": { "status": "ok" }
          }
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(StreamEvent.self, from: data)

        XCTAssertEqual(event.toolName, "shell")
        XCTAssertEqual(event.toolInput, #"{"command":"vm_stat"}"#)
        XCTAssertEqual(event.toolOutput, #"{"status":"ok"}"#)
    }
}

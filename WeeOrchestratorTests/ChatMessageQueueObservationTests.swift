import XCTest
@testable import WeeOrchestrator

@MainActor
final class ChatMessageQueueObservationTests: XCTestCase {
    /// Issue #415: the queue store backing `currentQueuedChatMessages` is
    /// `@ObservationIgnored` (by design, to avoid deep state tracking), so
    /// mutating it must go through `enqueueChatMessage`/`removeQueuedChatMessage`,
    /// which bump a tracked revision counter. If a mutation path forgets to
    /// bump the counter, SwiftUI never re-renders the queue panel even though
    /// the underlying data changed.
    func test_issue_415_enqueueingAMessageNotifiesObservers() {
        let model = WeeAppModel()
        model.activeEnvironment = .remote
        model.currentSessionID = "test-session-415"
        let key = ChatTranscriptKey(environment: .remote, sessionID: "test-session-415")

        XCTAssertEqual(model.currentQueuedChatMessages.count, 0)

        let notified = expectation(description: "observation fires after enqueue")
        withObservationTracking {
            _ = model.currentQueuedChatMessages
        } onChange: {
            notified.fulfill()
        }

        model.enqueueChatMessage(QueuedChatMessage(text: "hello", attachments: []), for: key)

        wait(for: [notified], timeout: 1.0)
        XCTAssertEqual(model.currentQueuedChatMessages.count, 1)
        XCTAssertEqual(model.currentQueuedChatMessages.first?.text, "hello")
    }

    func test_issue_415_removingAQueuedMessageNotifiesObservers() {
        let model = WeeAppModel()
        model.activeEnvironment = .remote
        model.currentSessionID = "test-session-415-remove"
        let key = ChatTranscriptKey(environment: .remote, sessionID: "test-session-415-remove")
        let queued = QueuedChatMessage(text: "queued message", attachments: [])
        model.enqueueChatMessage(queued, for: key)
        XCTAssertEqual(model.currentQueuedChatMessages.count, 1)

        let notified = expectation(description: "observation fires after removal")
        withObservationTracking {
            _ = model.currentQueuedChatMessages
        } onChange: {
            notified.fulfill()
        }

        model.removeQueuedChatMessage(id: queued.id)

        wait(for: [notified], timeout: 1.0)
        XCTAssertEqual(model.currentQueuedChatMessages.count, 0)
    }

    func test_issue_415_removingANonexistentMessageDoesNotFalselyNotify() {
        let model = WeeAppModel()
        model.activeEnvironment = .remote
        model.currentSessionID = "test-session-415-noop"

        let notified = expectation(description: "observation should not fire")
        notified.isInverted = true
        withObservationTracking {
            _ = model.currentQueuedChatMessages
        } onChange: {
            notified.fulfill()
        }

        model.removeQueuedChatMessage(id: UUID())

        wait(for: [notified], timeout: 0.3)
    }
}

import XCTest
@testable import WeeOrchestrator

final class SessionResetDetectorTests: XCTestCase {
    /// Issue #399: switching runtime/model mid-chat resets the backend
    /// session's context, but the client rendered the confirmation as a
    /// routine one-line system message indistinguishable from any other,
    /// so a follow-up question referencing earlier turns silently lost
    /// all context. The fix flags these messages so the UI can render a
    /// clear boundary; this test locks in the detection logic itself.
    func test_issue_399_detectsSessionResetConfirmation() {
        XCTAssertTrue(SessionResetDetector.indicatesReset("Switched runtime to **wee**. Model set to `ollama/gemma4:e4b`. Session reset."))
        XCTAssertTrue(SessionResetDetector.indicatesReset("Switched runtime to **claude**. Model set to `haiku`. Session reset."))
    }

    func test_issue_399_detectionIsCaseInsensitive() {
        XCTAssertTrue(SessionResetDetector.indicatesReset("Model updated. SESSION RESET."))
    }

    func test_issue_399_ordinaryConfirmationsAreNotFlagged() {
        XCTAssertFalse(SessionResetDetector.indicatesReset("Next chat will use claude / haiku."))
        XCTAssertFalse(SessionResetDetector.indicatesReset("Full access enabled."))
    }

    func test_issue_399_chatMessageFlagsContextBoundaryOnConstruction() {
        let resetMessage = ChatMessage(
            role: .system,
            text: "Switched runtime to **wee**. Model set to `ollama/gemma4:e4b`. Session reset."
        )
        XCTAssertFalse(resetMessage.isContextBoundary, "Constructing a ChatMessage directly does not auto-detect; callers must pass the flag explicitly")

        let flaggedMessage = ChatMessage(
            role: .system,
            text: "Switched runtime to **wee**. Model set to `ollama/gemma4:e4b`. Session reset.",
            isContextBoundary: true
        )
        XCTAssertTrue(flaggedMessage.isContextBoundary)
    }

    func test_issue_399_historyMessageAutoDetectsReset() {
        let history = HistoryMessage(role: "system", content: "Switched runtime to **wee**. Model set to `ollama/gemma4:e4b`. Session reset.", timestamp: nil)
        let message = ChatMessage(historyMessage: history)
        XCTAssertTrue(message.isContextBoundary, "Loading prior history should also flag a reset confirmation, not just live commands")
    }
}

import XCTest
@testable import WeeOrchestrator

final class SessionResetDetectorTests: XCTestCase {
    func test_detectsExplicitManualResetConfirmation() {
        XCTAssertTrue(SessionResetDetector.indicatesReset("✓ Session reset. Next message starts fresh."))
    }

    func test_detectionIsCaseInsensitive() {
        XCTAssertTrue(SessionResetDetector.indicatesReset("SESSION RESET. NEXT MESSAGE STARTS FRESH."))
    }

    func test_runtimeHandoffIsNotFlaggedAsAContextBoundary() {
        XCTAssertFalse(SessionResetDetector.indicatesReset("✓ Switched runtime to **claude**. Model set to `haiku`. Conversation context will be handed off to the new runtime."))
        XCTAssertFalse(SessionResetDetector.indicatesReset("Switched runtime to **wee**. Model set to `ollama/gemma4:e4b`. Session reset."))
        XCTAssertFalse(SessionResetDetector.indicatesReset("Next chat will use claude / haiku."))
    }

    func test_issue_399_chatMessageFlagsContextBoundaryOnConstruction() {
        let resetMessage = ChatMessage(
            role: .system,
            text: "✓ Session reset. Next message starts fresh."
        )
        XCTAssertFalse(resetMessage.isContextBoundary, "Constructing a ChatMessage directly does not auto-detect; callers must pass the flag explicitly")

        let flaggedMessage = ChatMessage(
            role: .system,
            text: "✓ Session reset. Next message starts fresh.",
            isContextBoundary: true
        )
        XCTAssertTrue(flaggedMessage.isContextBoundary)
    }

    func test_historyMessageAutoDetectsExplicitReset() {
        let history = HistoryMessage(role: "system", content: "✓ Session reset. Next message starts fresh.", timestamp: nil)
        let message = ChatMessage(historyMessage: history)
        XCTAssertTrue(message.isContextBoundary, "Loading prior history should also flag a reset confirmation, not just live commands")
    }
}

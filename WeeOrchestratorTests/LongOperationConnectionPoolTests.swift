import XCTest
@testable import WeeOrchestrator

@MainActor
final class LongOperationConnectionPoolTests: XCTestCase {
    /// Issue #48: chat streaming, file uploads, transcription, and
    /// text-to-speech all shared the same connection pool as every
    /// interactive request (session create, history, agents, kanban). A chat
    /// stream can stay open for up to five minutes, and sendChat()
    /// deliberately lets it keep running after the user navigates away, so
    /// several can be open across different threads at once. With enough of
    /// those parked on the shared six-connection-per-host pool, starting a
    /// new thread -- createSession() plus the sequential /agent, /runtime,
    /// /model, and /mode commands that can follow it -- queued behind them.
    private func makeClient(allowInsecureTLS: Bool = false) -> WeeAPIClient {
        WeeAPIClient(
            configuration: APIConfiguration(
                baseURLString: "http://127.0.0.1:9",
                token: "",
                identity: "",
                channel: "api",
                allowInsecureTLS: allowInsecureTLS
            )
        )
    }

    func test_issue_48_longOperationsUseAPoolSeparateFromInteractiveRequests() {
        let client = makeClient()

        XCTAssertFalse(
            client.longOperationSession === client.session,
            "A five-minute chat stream must not consume a connection from the interactive pool"
        )
    }

    func test_issue_48_longOperationsUseAPoolSeparateFromBrowserLongPolling() {
        let client = makeClient()

        XCTAssertFalse(
            client.longOperationSession === client.longPollSession,
            "Chat streaming and browser polling should not compete for the same small pool either"
        )
    }

    func test_issue_48_longOperationPoolIsSizedForSeveralConcurrentStreams() {
        let client = makeClient()

        XCTAssertGreaterThanOrEqual(
            client.longOperationSession.configuration.httpMaximumConnectionsPerHost,
            6,
            "Multiple chat threads can stream concurrently by design, unlike browser polling's single active poller"
        )
        XCTAssertGreaterThan(
            client.longOperationSession.configuration.timeoutIntervalForRequest,
            300,
            "The pool's own timeout must exceed the 300s chat-stream request timeout"
        )
    }

    func test_issue_48_insecureAndSecureLongOperationSessionsAreDistinctButStable() {
        let secure = makeClient()
        let insecure = makeClient(allowInsecureTLS: true)

        XCTAssertFalse(secure.longOperationSession === insecure.longOperationSession)
        XCTAssertTrue(
            secure.longOperationSession === makeClient().longOperationSession,
            "The pool must be shared across client instances, not rebuilt per request"
        )
    }
}

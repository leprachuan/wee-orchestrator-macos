import XCTest
@testable import WeeOrchestrator

final class LocalServiceSupervisionTests: XCTestCase {
    /// The Local API died and nothing brought it back: autoStart only runs at
    /// launch, so a crash — or a process killed from outside the app — left the
    /// service down silently. Every request then failed with URLError's stock
    /// "Could not connect to the server", which names neither the service nor
    /// the fix, and recovery was a manual Start the user had to know to find.

    // MARK: - Outage explanation

    func test_localOutageIsExplainedInsteadOfARawTransportError() throws {
        let message = try XCTUnwrap(
            WeeAppModel.localServiceOutageExplanation(
                for: URLError(.cannotConnectToHost),
                environment: .local,
                isLocalServiceRunning: false,
                baseURL: "http://127.0.0.1:8001"
            )
        )
        XCTAssertTrue(message.contains("Local API is not running"))
        XCTAssertTrue(message.contains("127.0.0.1:8001"), "name the endpoint that refused")
        XCTAssertTrue(message.contains("Settings"), "say where to fix it")
    }

    /// The same failure against Remote means the network or the remote host.
    /// Telling someone to start a local service would send them the wrong way.
    func test_remoteEnvironmentIsNotBlamedOnTheLocalService() {
        XCTAssertNil(
            WeeAppModel.localServiceOutageExplanation(
                for: URLError(.cannotConnectToHost),
                environment: .remote,
                isLocalServiceRunning: false,
                baseURL: "https://100.124.186.75:8000"
            )
        )
    }

    func test_runningLocalServiceIsNotBlamedForAConnectionFailure() {
        XCTAssertNil(
            WeeAppModel.localServiceOutageExplanation(
                for: URLError(.cannotConnectToHost),
                environment: .local,
                isLocalServiceRunning: true,
                baseURL: "http://127.0.0.1:8001"
            )
        )
    }

    func test_unrelatedErrorsAreLeftAlone() {
        XCTAssertNil(
            WeeAppModel.localServiceOutageExplanation(
                for: URLError(.badServerResponse),
                environment: .local,
                isLocalServiceRunning: false,
                baseURL: "http://127.0.0.1:8001"
            )
        )
        XCTAssertNil(
            WeeAppModel.localServiceOutageExplanation(
                for: WeeAPIError.httpStatus(500, "boom"),
                environment: .local,
                isLocalServiceRunning: false,
                baseURL: "http://127.0.0.1:8001"
            )
        )
    }

    func test_missingBaseURLStillProducesUsableText() throws {
        let message = try XCTUnwrap(
            WeeAppModel.localServiceOutageExplanation(
                for: URLError(.cannotFindHost),
                environment: .local,
                isLocalServiceRunning: false,
                baseURL: "   "
            )
        )
        XCTAssertFalse(message.contains("  "), "must not leave a blank where the URL goes")
        XCTAssertTrue(message.contains("local backend"))
    }

    // MARK: - Restart budget

    /// Bounded on purpose: a service that cannot stay up is a real problem the
    /// user needs to see, not something to relaunch forever.
    func test_restartBudgetIsBoundedAndBacksOff() {
        XCTAssertGreaterThan(WeeAppModel.maximumLocalAPIRestartAttempts, 0)
        XCTAssertLessThanOrEqual(WeeAppModel.maximumLocalAPIRestartAttempts, 5)

        let backoff = WeeAppModel.localAPIRestartBackoff
        XCTAssertFalse(backoff.isEmpty)
        XCTAssertEqual(backoff, backoff.sorted(), "delays must not shrink between attempts")
        XCTAssertGreaterThan(backoff.first ?? 0, 0, "an immediate retry would spin")
    }

    /// The budget clears only after the service proves it can stay up.
    /// Resetting on launch would let a crash-loop restart forever, since every
    /// attempt would look like a fresh first failure.
    func test_stableUptimeThresholdOutlastsTheWholeBackoffWindow() {
        let totalBackoff = WeeAppModel.localAPIRestartBackoff.reduce(0, +)
        XCTAssertGreaterThan(
            WeeAppModel.localAPIStableUptimeSeconds,
            totalBackoff,
            "a service dying inside the retry window must not be treated as stable"
        )
    }
}

import XCTest
@testable import WeeOrchestrator

@MainActor
final class BrowserPollerLifecycleTests: XCTestCase {
    /// Issue #47: every visited thread left its browser command poller running, and each
    /// poller parks a 25-second long poll on a URLSession connection. Once six pollers were
    /// alive the six-connection-per-host pool was exhausted and the next thread switch or
    /// thread creation stalled 25-45 seconds waiting for a connection.
    private func makeClient() -> WeeAPIClient {
        WeeAPIClient(
            configuration: APIConfiguration(
                baseURLString: "http://127.0.0.1:9",
                token: "",
                identity: "",
                channel: "api",
                allowInsecureTLS: false
            )
        )
    }

    private func makeStore() -> BrowserSessionStore {
        let store = BrowserSessionStore()
        addTeardownBlock { @MainActor in store.deactivateAll() }
        return store
    }

    func test_issue_47_activatingASessionStopsThePreviousSessionsPoller() {
        let store = makeStore()
        let client = makeClient()

        let first = store.activate(environment: .local, sessionID: "session-a", client: client)
        XCTAssertTrue(first.isPolling, "The newly activated session should be polling")

        let second = store.activate(environment: .local, sessionID: "session-b", client: client)
        XCTAssertFalse(
            first.isPolling,
            "Switching threads must stop the previous thread's poller so it releases its connection"
        )
        XCTAssertTrue(second.isPolling)
    }

    func test_issue_47_visitingManyThreadsLeavesOnlyOneLivePoller() {
        let store = makeStore()
        let client = makeClient()

        // More threads than the six-connection-per-host pool, which is what used to
        // exhaust it.
        for index in 0..<8 {
            store.activate(environment: .local, sessionID: "session-\(index)", client: client)
        }

        XCTAssertEqual(
            store.pollingControllerCount,
            1,
            "Only the active thread may hold a long-poll connection, regardless of how many threads were visited"
        )
    }

    func test_issue_47_reactivatingTheSameSessionKeepsItsExistingPoller() {
        let store = makeStore()
        let client = makeClient()

        let first = store.activate(environment: .local, sessionID: "session-a", client: client)
        let again = store.activate(environment: .local, sessionID: "session-a", client: client)

        XCTAssertTrue(again === first, "Re-selecting a thread should reuse its controller")
        XCTAssertTrue(again.isPolling)
        XCTAssertEqual(store.pollingControllerCount, 1)
    }

    func test_issue_47_sameSessionIDInADifferentEnvironmentIsATreatedAsADistinctThread() {
        let store = makeStore()
        let client = makeClient()

        let local = store.activate(environment: .local, sessionID: "shared-id", client: client)
        let remote = store.activate(environment: .remote, sessionID: "shared-id", client: client)

        XCTAssertFalse(local === remote, "Environment is part of the session identity")
        XCTAssertFalse(local.isPolling, "Switching environments must also release the old poller")
        XCTAssertEqual(store.pollingControllerCount, 1)
    }

    func test_issue_47_deactivateAllStopsEveryPoller() {
        let store = makeStore()
        let client = makeClient()

        store.activate(environment: .local, sessionID: "session-a", client: client)
        store.activate(environment: .local, sessionID: "session-b", client: client)
        store.deactivateAll()

        XCTAssertEqual(
            store.pollingControllerCount,
            0,
            "Deselecting every thread should leave no connections held"
        )
        XCTAssertNil(store.activeSessionKey)
    }

    func test_issue_47_disconnectIsIdempotent() {
        let store = makeStore()
        let client = makeClient()

        let controller = store.activate(environment: .local, sessionID: "session-a", client: client)
        controller.disconnect()
        controller.disconnect()

        XCTAssertFalse(controller.isPolling)
    }

    func test_issue_47_aDisconnectedControllerCanPollAgainWhenReselected() {
        let store = makeStore()
        let client = makeClient()

        let first = store.activate(environment: .local, sessionID: "session-a", client: client)
        store.activate(environment: .local, sessionID: "session-b", client: client)
        XCTAssertFalse(first.isPolling)

        let reselected = store.activate(environment: .local, sessionID: "session-a", client: client)
        XCTAssertTrue(reselected === first)
        XCTAssertTrue(reselected.isPolling, "Returning to a thread must restart its poller")
        XCTAssertEqual(store.pollingControllerCount, 1)
    }

    /// Issue #50: every distinct thread visited left a cached
    /// BrowserSessionController alive for the lifetime of the app, and each one
    /// owns a WKWebView with its own WebKit helper processes. Memory and helper
    /// count grew all day until the app was relaunched.
    func test_issue_50_visitingManyThreadsDoesNotCacheAControllerForEachOne() {
        let store = makeStore()
        let client = makeClient()

        for index in 0..<20 {
            store.activate(environment: .local, sessionID: "session-\(index)", client: client)
        }

        XCTAssertLessThanOrEqual(
            store.cachedControllerCount,
            BrowserSessionStore.maximumCachedSessions,
            "Cached web views must be bounded, not one per thread ever visited"
        )
    }

    func test_issue_50_evictionNeverDiscardsTheActiveSession() {
        let store = makeStore()
        let client = makeClient()

        let active = store.activate(environment: .local, sessionID: "keep-me", client: client)
        for index in 0..<20 {
            _ = store.controller(environment: .local, sessionID: "other-\(index)", client: client)
        }

        XCTAssertTrue(
            store.activate(environment: .local, sessionID: "keep-me", client: client) === active,
            "The session being viewed must survive eviction rather than being rebuilt underneath the user"
        )
    }

    func test_issue_50_evictionStopsTheEvictedSessionsPoller() {
        let store = makeStore()
        let client = makeClient()

        let first = store.activate(environment: .local, sessionID: "session-0", client: client)
        for index in 1...BrowserSessionStore.maximumCachedSessions + 2 {
            store.activate(environment: .local, sessionID: "session-\(index)", client: client)
        }

        XCTAssertFalse(first.isPolling, "An evicted controller must not leave its poller running")
        XCTAssertEqual(store.pollingControllerCount, 1)
    }

    func test_issue_47_longPollsUseAConnectionPoolSeparateFromInteractiveRequests() {
        let client = makeClient()

        XCTAssertFalse(
            client.longPollSession === client.session,
            "A parked long poll must not consume a connection from the interactive pool"
        )
        XCTAssertEqual(
            client.longPollSession.configuration.httpMaximumConnectionsPerHost,
            4,
            "The long-poll pool should be explicitly sized rather than inheriting the default"
        )
        XCTAssertGreaterThan(
            client.longPollSession.configuration.timeoutIntervalForRequest,
            25,
            "The request timeout must exceed the server's 25s long-poll window"
        )
    }

    func test_issue_47_insecureAndSecureLongPollSessionsAreDistinctButStable() {
        let secure = makeClient()
        var insecureConfiguration = secure.configuration
        insecureConfiguration.allowInsecureTLS = true
        let insecure = WeeAPIClient(configuration: insecureConfiguration)

        XCTAssertFalse(secure.longPollSession === insecure.longPollSession)
        XCTAssertTrue(
            secure.longPollSession === makeClient().longPollSession,
            "The long-poll session must be shared across clients, not rebuilt per request"
        )
    }
}

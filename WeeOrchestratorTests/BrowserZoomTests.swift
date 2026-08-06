import XCTest
@testable import WeeOrchestrator

@MainActor
final class BrowserZoomTests: XCTestCase {
    private func makeController() -> BrowserSessionController {
        // Start every test from a known zoom level: BrowserSessionController
        // seeds itself from persisted UserDefaults state, which would
        // otherwise leak between tests (and real launches).
        BrowserSessionController.persistedZoomLevel = 1.0
        return BrowserSessionController(
            sessionKey: "test-session",
            sessionID: "test-session-id",
            client: WeeAPIClient(configuration: .defaults)
        )
    }

    func test_startsAtPersistedZoomLevel() {
        BrowserSessionController.persistedZoomLevel = 1.5
        let controller = BrowserSessionController(
            sessionKey: "test-session",
            sessionID: "test-session-id",
            client: WeeAPIClient(configuration: .defaults)
        )
        XCTAssertEqual(controller.zoomLevel, 1.5)
        XCTAssertEqual(controller.webView.pageZoom, 1.5)
    }

    func test_zoomInIncreasesLevelAndAppliesToWebView() {
        let controller = makeController()
        controller.zoomIn()
        XCTAssertEqual(controller.zoomLevel, 1.1, accuracy: 0.001)
        XCTAssertEqual(controller.webView.pageZoom, 1.1, accuracy: 0.001)
    }

    func test_zoomOutDecreasesLevel() {
        let controller = makeController()
        controller.zoomOut()
        XCTAssertEqual(controller.zoomLevel, 0.9, accuracy: 0.001)
    }

    func test_zoomInClampsAtUpperBound() {
        let controller = makeController()
        for _ in 0..<50 { controller.zoomIn() }
        XCTAssertEqual(controller.zoomLevel, BrowserSessionController.zoomRange.upperBound)
    }

    func test_zoomOutClampsAtLowerBound() {
        let controller = makeController()
        for _ in 0..<50 { controller.zoomOut() }
        XCTAssertEqual(controller.zoomLevel, BrowserSessionController.zoomRange.lowerBound)
    }

    func test_resetZoomReturnsToOneHundredPercent() {
        let controller = makeController()
        controller.zoomIn()
        controller.zoomIn()
        controller.resetZoom()
        XCTAssertEqual(controller.zoomLevel, 1.0)
        XCTAssertEqual(controller.webView.pageZoom, 1.0)
    }

    func test_zoomLevelPersistsAcrossControllerInstances() {
        let first = makeController()
        first.zoomIn()
        first.zoomIn()

        let second = BrowserSessionController(
            sessionKey: "another-session",
            sessionID: "another-session-id",
            client: WeeAPIClient(configuration: .defaults)
        )
        XCTAssertEqual(second.zoomLevel, first.zoomLevel, accuracy: 0.001)
    }
}

import XCTest
@testable import WeeOrchestrator

/// Issue #69: multi-tab support in the session browser. Each tab owns an
/// independent `WKWebView`; these tests exercise tab creation, selection,
/// and closing without touching real page loads.
@MainActor
final class BrowserTabsTests: XCTestCase {
    private func makeController() -> BrowserSessionController {
        BrowserSessionController(
            sessionKey: "test-session",
            sessionID: "test-session-id",
            client: WeeAPIClient(configuration: .defaults)
        )
    }

    func test_newSessionStartsWithExactlyOneTab() {
        let controller = makeController()
        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.activeTabID, controller.tabs[0].id)
    }

    func test_newTabIsAppendedAndBecomesActive() {
        let controller = makeController()
        let firstTabID = controller.tabs[0].id

        let newTab = controller.newTab()

        XCTAssertEqual(controller.tabs.count, 2)
        XCTAssertEqual(controller.activeTabID, newTab.id)
        XCTAssertNotEqual(newTab.id, firstTabID)
    }

    func test_selectTabChangesActiveTabAndAddressBar() {
        let controller = makeController()
        let firstTabID = controller.activeTabID
        controller.address = "https://one.example"

        let secondTab = controller.newTab()
        controller.address = "https://two.example"

        controller.selectTab(firstTabID)
        XCTAssertEqual(controller.activeTabID, firstTabID)
        XCTAssertEqual(controller.address, "https://one.example")

        controller.selectTab(secondTab.id)
        XCTAssertEqual(controller.activeTabID, secondTab.id)
        XCTAssertEqual(controller.address, "https://two.example")
    }

    func test_selectingAnUnknownTabIDIsANoOp() {
        let controller = makeController()
        let activeBefore = controller.activeTabID

        controller.selectTab(BrowserTab.ID())

        XCTAssertEqual(controller.activeTabID, activeBefore)
    }

    func test_closingTheLastTabIsANoOp() {
        let controller = makeController()
        let onlyTabID = controller.activeTabID

        controller.closeTab(onlyTabID)

        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.activeTabID, onlyTabID)
    }

    func test_closingTheActiveTabActivatesAnotherTab() {
        let controller = makeController()
        let firstTabID = controller.activeTabID
        let secondTab = controller.newTab()

        controller.closeTab(secondTab.id)

        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.activeTabID, firstTabID)
    }

    func test_closingANonActiveTabDoesNotChangeTheActiveTab() {
        let controller = makeController()
        let firstTab = controller.tabs[0]
        let secondTab = controller.newTab()
        controller.selectTab(firstTab.id)

        controller.closeTab(secondTab.id)

        XCTAssertEqual(controller.tabs.count, 1)
        XCTAssertEqual(controller.activeTabID, firstTab.id)
    }

    func test_eachTabTracksItsOwnAddressIndependently() {
        let controller = makeController()
        controller.address = "https://first.example"
        let secondTab = controller.newTab()
        controller.address = "https://second.example"

        XCTAssertEqual(controller.tabs[0].address, "https://first.example")
        XCTAssertEqual(secondTab.address, "https://second.example")
    }
}

import XCTest
@testable import WeeOrchestrator

final class ContentViewMinimumWidthTests: XCTestCase {
    /// Issue #55: `HSplitView` panes (session list, chat, shell, browser) each enforce
    /// their own minimum width, but the window's own minimum width was a flat 1180pt
    /// regardless of how many panels were visible. Opening the shell panel on top of an
    /// already-visible session list and browser pushed the sum of pane minimums past the
    /// window's floor, forcing AppKit to compress panes below their stated minimums —
    /// the same compression that produced issue #54's overlapping navigation controls.

    func test_issue_55_defaultChatConfigurationMatchesTheShippedBaselineFloor() {
        let width = ContentView.minimumWindowWidth(
            section: .chat,
            railCollapsed: false,
            sessionListVisible: true,
            shellVisible: false,
            browserVisible: true
        )
        XCTAssertEqual(width, 1180, "The default panel configuration must not regress the window size this app has always shipped with")
    }

    func test_issue_55_openingTheShellPanelGrowsTheWindowMinimumToFitIt() {
        let withoutShell = ContentView.minimumWindowWidth(
            section: .chat, railCollapsed: false, sessionListVisible: true, shellVisible: false, browserVisible: true
        )
        let withShell = ContentView.minimumWindowWidth(
            section: .chat, railCollapsed: false, sessionListVisible: true, shellVisible: true, browserVisible: true
        )
        // Without the shell pane, the raw sum (rail 196 + list 220 + chat 440 + browser 300 = 1156)
        // is below the 1180 baseline floor, so the baseline wins; opening the shell pushes the raw
        // sum to 1456, which now exceeds the baseline and must be reflected in the window's minimum.
        XCTAssertEqual(withoutShell, 1180)
        XCTAssertEqual(withShell, 1456)
        XCTAssertGreaterThan(withShell, withoutShell, "Opening the shell panel must grow the window's minimum so its pane is never compressed below its own floor")
    }

    func test_issue_55_everyPanelOpenSimultaneouslyNeverCompressesBelowPaneMinimums() {
        let width = ContentView.minimumWindowWidth(
            section: .chat, railCollapsed: false, sessionListVisible: true, shellVisible: true, browserVisible: true
        )
        // rail(196) + sessionList(220) + chat(440) + shell(300) + browser(300)
        XCTAssertEqual(width, 1456)
    }

    func test_issue_55_collapsingTheSessionListShrinksButDoesNotHideIt() {
        // Both shell and browser visible so the raw sum exceeds the 1180 baseline floor in both
        // the expanded and collapsed cases, letting the session list's own contribution show
        // through undistorted by clamping.
        let expanded = ContentView.minimumWindowWidth(
            section: .chat, railCollapsed: false, sessionListVisible: true, shellVisible: true, browserVisible: true
        )
        let collapsed = ContentView.minimumWindowWidth(
            section: .chat, railCollapsed: false, sessionListVisible: false, shellVisible: true, browserVisible: true
        )
        XCTAssertLessThan(collapsed, expanded, "Collapsing the session list should reduce the required width")
        XCTAssertEqual(expanded - collapsed, 220 - 56, "The collapsed rail must still claim its own (non-zero) width rather than vanishing")
    }

    func test_issue_55_nonChatSectionsIgnorePanelStateAndUseTheBaselineFloor() {
        let width = ContentView.minimumWindowWidth(
            section: .settings, railCollapsed: false, sessionListVisible: true, shellVisible: true, browserVisible: true
        )
        XCTAssertEqual(width, 1180, "Settings/Kanban/etc. have no shell or browser panes, so panel visibility must not affect their floor")
    }

    func test_issue_55_collapsingTheWorkspaceRailNeverShrinksBelowTheBaselineFloor() {
        let width = ContentView.minimumWindowWidth(
            section: .chat, railCollapsed: true, sessionListVisible: false, shellVisible: false, browserVisible: false
        )
        XCTAssertGreaterThanOrEqual(width, 1180, "The window must never be allowed to shrink below the app's baseline floor")
    }
}

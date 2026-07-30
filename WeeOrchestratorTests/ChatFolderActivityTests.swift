import XCTest
@testable import WeeOrchestrator

final class ChatFolderActivityTests: XCTestCase {
    /// Issue #462: a collapsed agent folder hid every session-level spinner
    /// inside it, so a still-running query looked finished.
    func test_issue_462_collapsedFolderWithRunningSessionShowsIndicator() {
        XCTAssertTrue(ChatFolderActivity.showsIndicator(isExpanded: false, runningSessionCount: 1))
        XCTAssertTrue(ChatFolderActivity.showsIndicator(isExpanded: false, runningSessionCount: 4))
    }

    func test_issue_462_collapsedFolderWithNothingRunningStaysQuiet() {
        XCTAssertFalse(ChatFolderActivity.showsIndicator(isExpanded: false, runningSessionCount: 0))
    }

    /// An expanded folder already shows a spinner on each running session, so a
    /// second indicator on the folder would read as separate work.
    func test_issue_462_expandedFolderDefersToPerSessionSpinners() {
        XCTAssertFalse(ChatFolderActivity.showsIndicator(isExpanded: true, runningSessionCount: 3))
        XCTAssertFalse(ChatFolderActivity.showsIndicator(isExpanded: true, runningSessionCount: 0))
    }

    func test_issue_462_helpTextAgreesInNumber() {
        XCTAssertEqual(ChatFolderActivity.indicatorHelp(runningSessionCount: 1), "1 chat in this folder is running")
        XCTAssertTrue(ChatFolderActivity.indicatorHelp(runningSessionCount: 3).contains("3 chats"))
    }
}

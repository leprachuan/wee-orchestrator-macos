import XCTest
@testable import WeeOrchestrator

@MainActor
final class BackgroundTaskAutoRefreshTests: XCTestCase {
    /// Issue #20: background task status should poll on its own every ~60s.
    /// Same as the hourly update-check loop, bootstrap() re-running per
    /// window against the shared model must not spawn a duplicate poller.
    func test_startingTheLoopTwiceOnlyStartsOneTask() {
        let model = WeeAppModel()
        XCTAssertEqual(model.backgroundTaskAutoRefreshLoopStartCount, 0)

        model.startBackgroundTaskAutoRefreshLoopIfNeeded()
        XCTAssertEqual(model.backgroundTaskAutoRefreshLoopStartCount, 1)
        XCTAssertNotNil(model.backgroundTaskAutoRefreshTask)

        model.startBackgroundTaskAutoRefreshLoopIfNeeded()
        XCTAssertEqual(model.backgroundTaskAutoRefreshLoopStartCount, 1, "a second call must not start a second loop")

        model.backgroundTaskAutoRefreshTask?.cancel()
    }
}

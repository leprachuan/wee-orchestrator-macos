import XCTest
@testable import WeeOrchestrator

@MainActor
final class HourlyUpdateCheckTests: XCTestCase {
    /// Issue #19: bootstrap() re-runs for every window (`.task` on
    /// ContentView, one per WindowGroup instance, against the same shared
    /// model), so the hourly update-check loop must not spawn a duplicate
    /// timer per window.
    func test_startingTheLoopTwiceOnlyStartsOneTask() {
        let model = WeeAppModel()
        XCTAssertEqual(model.hourlyUpdateCheckLoopStartCount, 0)

        model.startHourlyUpdateCheckLoopIfNeeded()
        XCTAssertEqual(model.hourlyUpdateCheckLoopStartCount, 1)
        XCTAssertNotNil(model.hourlyUpdateCheckTask)

        model.startHourlyUpdateCheckLoopIfNeeded()
        XCTAssertEqual(model.hourlyUpdateCheckLoopStartCount, 1, "a second call must not start a second loop")

        model.hourlyUpdateCheckTask?.cancel()
    }
}

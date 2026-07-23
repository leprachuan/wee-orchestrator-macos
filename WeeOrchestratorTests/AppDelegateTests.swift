import XCTest
@testable import WeeOrchestrator

private final class StopLocalAPISpy: LocalServiceStoppable {
    private(set) var terminationCallCount = 0
    func stopLocalAPIForApplicationTermination() { terminationCallCount += 1 }
}

final class AppDelegateTests: XCTestCase {
    /// Issue #7: quitting the app left its local API subprocess
    /// (`agent_manager.py --api`) running as an orphan because nothing called
    /// `stopLocalAPI()` on quit — there was no NSApplicationDelegate at all.
    /// This locks in that `applicationWillTerminate` actually stops it.
    func test_applicationWillTerminate_delegatesToTheLifecycleStopHook() {
        let spy = StopLocalAPISpy()
        let delegate = AppDelegate()
        delegate.model = spy

        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertEqual(spy.terminationCallCount, 1)
    }

    func test_issue_7_applicationWillTerminate_toleratesNilModel() {
        let delegate = AppDelegate()
        delegate.model = nil

        // Should not crash when no model has been wired up yet.
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
}

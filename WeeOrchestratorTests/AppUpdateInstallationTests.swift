import XCTest
@testable import WeeOrchestrator

final class AppUpdateInstallationTests: XCTestCase {
    @MainActor
    func testReplacementScriptWaitsForOriginalProcessBeforeReplacingBundle() {
        let script = WeeAppModel.appReplacementScript

        XCTAssertTrue(script.contains("old_pid=\"$3\""))
        XCTAssertTrue(script.contains("/bin/kill -0 \"$old_pid\""))
        XCTAssertTrue(script.contains("attempts"))

        let waitRange = try! XCTUnwrap(script.range(of: "while /bin/kill -0"))
        let replaceRange = try! XCTUnwrap(script.range(of: "mv \"$target\" \"$backup\""))
        XCTAssertLessThan(waitRange.lowerBound, replaceRange.lowerBound)
    }

    @MainActor
    func testReplacementUsesDetachedNoHupLauncher() {
        XCTAssertEqual(WeeAppModel.appReplacementLauncher, "/usr/bin/nohup")
    }

    @MainActor
    func testKeepRunningAPIIsPreservedAcrossApplicationTermination() {
        let model = WeeAppModel()
        model.keepLocalAPIRunningAfterAppQuits = true

        XCTAssertFalse(model.shouldStopLocalAPIForApplicationTermination)
    }

    /// Regression test: a real install (v0.8.0, Jul 25) sat on "Installing…"
    /// for two days straight. NSApp.terminate() never landed, and the
    /// detached helper's own poll loop gives up silently after 30 attempts —
    /// nothing reset isInstallingAppUpdate, so the UI was stuck forever with
    /// no error and no retry. The watchdog must recover on its own if this
    /// process is still running well after asking AppKit to quit.
    @MainActor
    func testStuckInstallResetsUIInsteadOfHangingForever() async throws {
        let model = WeeAppModel()
        let version = try XCTUnwrap(AppSemanticVersion("0.9.0"))
        model.isInstallingAppUpdate = true
        model.appUpdateStatus = "Installing Wee Orchestrator 0.9.0…"

        // A real quit would tear down the whole process before a 10-second
        // timeout ever elapses; this short one exercises the same code
        // without an actual multi-second test.
        await model.watchdogStuckAppUpdateInstall(version: version, timeout: .milliseconds(10))

        XCTAssertFalse(model.isInstallingAppUpdate, "must not stay stuck on the spinner forever")
        let status = try XCTUnwrap(model.appUpdateStatus)
        XCTAssertTrue(status.contains("0.9.0"))
        XCTAssertTrue(status.lowercased().contains("quit"), "must tell the user what to do next")
    }
}

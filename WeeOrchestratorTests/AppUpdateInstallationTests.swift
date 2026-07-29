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

    private func makePendingUpdate(version: String) throws -> MacAppUpdate {
        MacAppUpdate(
            version: try XCTUnwrap(AppSemanticVersion(version)),
            releaseNotes: "",
            // RFC 2606 reserves .invalid so this is guaranteed to fail DNS
            // resolution immediately rather than depend on real network
            // conditions -- if the retry path reaches this URL at all, the
            // test needs that failure to be fast and deterministic.
            archiveURL: try XCTUnwrap(URL(string: "https://update.invalid/nonexistent.zip")),
            checksumURL: nil,
            bodyChecksum: nil
        )
    }

    /// Regression test: clicking "Update and Restart" a second time, after
    /// the watchdog above already fired once, visibly did nothing. That
    /// button re-ran installAvailableAppUpdate() from scratch -- a redundant
    /// re-download and re-verify, a second scheduleAppReplacement() spawning
    /// a helper that raced the first attempt's still-running one, and a
    /// repeat of the exact NSApp.terminate() call that had already failed to
    /// bring the process down within the watchdog's window. Retrying must
    /// instead recognize that a replacement is already staged and force the
    /// exit directly, without touching the network again.
    @MainActor
    func test_issue_49_retryForceQuitsWithoutRedownloadingWhileHelperIsStillRunning() async throws {
        let model = WeeAppModel()
        model.availableAppUpdate = try makePendingUpdate(version: "9.9.9")

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        helper.arguments = ["30"]
        try helper.run()
        defer { helper.terminate() }
        model.appReplacementProcess = helper

        var forceQuitCallCount = 0
        model.forceQuitOverrideForTesting = { forceQuitCallCount += 1 }

        await model.installAvailableAppUpdate()

        XCTAssertEqual(
            forceQuitCallCount,
            1,
            "retry must force the exit the first attempt's NSApp.terminate() could not"
        )
        XCTAssertTrue(model.isInstallingAppUpdate, "must not fall through to the download/verify pipeline")
        let status = try XCTUnwrap(model.appUpdateStatus)
        XCTAssertTrue(status.contains("Installing"))
        XCTAssertFalse(status.lowercased().contains("failed"), "must not have attempted a redundant download")
    }

    /// Companion to the test above: when nothing is staged yet (a fresh
    /// attempt, or a previous helper that already exited), retry must still
    /// go through the full pipeline rather than force-quitting into a void
    /// with no helper left to perform the swap.
    @MainActor
    func test_issue_49_installWithNoStagedReplacementDoesNotForceQuit() async throws {
        let model = WeeAppModel()
        model.availableAppUpdate = try makePendingUpdate(version: "9.9.9")

        var forceQuitCallCount = 0
        model.forceQuitOverrideForTesting = { forceQuitCallCount += 1 }

        await model.installAvailableAppUpdate()

        XCTAssertEqual(forceQuitCallCount, 0, "must not force-quit when no replacement is staged")
        XCTAssertFalse(model.isInstallingAppUpdate)
        let status = try XCTUnwrap(model.appUpdateStatus)
        XCTAssertFalse(status.contains("Installing"), "must have attempted the real pipeline, not taken the retry shortcut")
    }
}

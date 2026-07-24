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
}

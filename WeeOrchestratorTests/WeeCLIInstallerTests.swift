import XCTest
@testable import WeeOrchestrator

final class WeeCLIInstallerTests: XCTestCase {
    private var temporaryHome: URL!

    override func setUpWithError() throws {
        temporaryHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("wee-cli-installer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryHome)
    }

    func testInstallCreatesExecutableLauncherAndShellPath() throws {
        let installation = try WeeCLIInstaller.install(
            homeDirectory: temporaryHome,
            workingDirectory: "~/Developer/Current Wee",
            checkoutDirectory: "~/Developer/Wee-Orchestrator"
        )

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installation.launcherURL.path))
        let launcher = try String(contentsOf: installation.launcherURL, encoding: .utf8)
        let managed = WeeCLIInstaller.managedCheckoutURL(homeDirectory: temporaryHome).path
        XCTAssertTrue(launcher.contains(managed))
        XCTAssertLessThan(
            launcher.range(of: managed)!.lowerBound,
            launcher.range(of: temporaryHome.appendingPathComponent("Developer/Current Wee").path)!.lowerBound
        )
        XCTAssertTrue(launcher.contains(temporaryHome.appendingPathComponent("Developer/Current Wee").path))
        XCTAssertTrue(launcher.contains("exec \"$python\" \"$source_dir/wee_cli.py\" \"$@\""))

        for profile in installation.shellProfileURLs {
            let contents = try String(contentsOf: profile, encoding: .utf8)
            XCTAssertTrue(contents.contains("$HOME/.local/bin"))
        }
    }

    func testInstallIsIdempotentAndRepairsLauncher() throws {
        let zprofile = temporaryHome.appendingPathComponent(".zprofile")
        try "export EXISTING=value\n".write(to: zprofile, atomically: true, encoding: .utf8)

        _ = try WeeCLIInstaller.install(
            homeDirectory: temporaryHome,
            workingDirectory: "/first/source",
            checkoutDirectory: "/checkout"
        )
        let second = try WeeCLIInstaller.install(
            homeDirectory: temporaryHome,
            workingDirectory: "/second/source",
            checkoutDirectory: "/checkout"
        )

        let profile = try String(contentsOf: zprofile, encoding: .utf8)
        XCTAssertEqual(profile.components(separatedBy: "# >>> Wee Orchestrator CLI >>>").count - 1, 1)
        XCTAssertTrue(profile.contains("export EXISTING=value"))

        let launcher = try String(contentsOf: second.launcherURL, encoding: .utf8)
        XCTAssertFalse(launcher.contains("/first/source"))
        XCTAssertTrue(launcher.contains("/second/source"))
    }

    func testLauncherSafelyQuotesCheckoutPaths() {
        let launcher = WeeCLIInstaller.launcherScript(
            workingDirectory: "/Users/example/Wee's Runtime",
            checkoutDirectory: "/tmp/checkout"
        )
        XCTAssertTrue(launcher.contains("'/Users/example/Wee'\\''s Runtime'"))
    }
}

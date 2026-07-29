import XCTest
@testable import WeeOrchestrator

final class LocalServiceEnvironmentTests: XCTestCase {
    /// Issue #51: a Finder-launched app inherits launchd's minimal
    /// PATH=/usr/bin:/bin:/usr/sbin:/sbin. The Local API shells out to `gh` for
    /// the Kanban board, which lives in Homebrew's prefix, so
    /// subprocess.run(["gh", ...]) raised FileNotFoundError and the board
    /// returned a bare 500 "Internal server error" -- but only when the app was
    /// launched from Finder, which is why it never reproduced from a terminal.
    private static let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    func test_issue_51_homebrewToolsAreReachableFromTheLaunchdPath() {
        let path = WeeAppModel.localServicePath(inheriting: Self.launchdPath)
        let entries = path.split(separator: ":").map(String.init)

        XCTAssertTrue(entries.contains("/opt/homebrew/bin"), "gh lives here on Apple Silicon")
        XCTAssertTrue(entries.contains("/usr/local/bin"), "and here on Intel")
    }

    func test_issue_51_inheritedPathEntriesArePreserved() {
        let path = WeeAppModel.localServicePath(inheriting: Self.launchdPath)
        let entries = path.split(separator: ":").map(String.init)

        for inherited in Self.launchdPath.split(separator: ":").map(String.init) {
            XCTAssertTrue(entries.contains(inherited), "must not drop \(inherited) from the inherited PATH")
        }
    }

    func test_issue_51_toolDirectoriesTakePrecedenceOverInheritedEntries() {
        let path = WeeAppModel.localServicePath(inheriting: Self.launchdPath)
        let entries = path.split(separator: ":").map(String.init)

        let homebrew = try? XCTUnwrap(entries.firstIndex(of: "/opt/homebrew/bin"))
        let usrBin = try? XCTUnwrap(entries.firstIndex(of: "/usr/bin"))
        XCTAssertLessThan(homebrew ?? .max, usrBin ?? .min)
    }

    func test_issue_51_anAlreadyCompletePathIsNotDuplicated() {
        // A terminal-launched app already has Homebrew on PATH; prepending it a
        // second time would be harmless but sloppy, and makes the value churn
        // depending on how the app happened to be started.
        let full = "/opt/homebrew/bin:/usr/local/bin:\(Self.launchdPath)"
        let path = WeeAppModel.localServicePath(inheriting: full)
        let entries = path.split(separator: ":").map(String.init)

        XCTAssertEqual(entries.filter { $0 == "/opt/homebrew/bin" }.count, 1)
        XCTAssertEqual(entries.filter { $0 == "/usr/local/bin" }.count, 1)
    }

    func test_issue_51_anEmptyOrMissingInheritedPathStillYieldsToolDirectories() {
        for inherited in [nil, "", ":"] as [String?] {
            let entries = WeeAppModel.localServicePath(inheriting: inherited)
                .split(separator: ":").map(String.init)
            XCTAssertTrue(entries.contains("/opt/homebrew/bin"), "inherited=\(String(describing: inherited))")
            XCTAssertFalse(entries.contains(""), "must not emit empty PATH entries")
        }
    }
}

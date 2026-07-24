import XCTest
@testable import WeeOrchestrator

/// Issue #28: after a successful Ollama pull the app restarts the Local API but
/// previously left the macOS model catalog stale, so a freshly downloaded model
/// did not appear in the chat picker until a manual refresh or app restart.
final class WeeCatalogRefreshTests: XCTestCase {
    @MainActor
    func testPulledModelIsMatchedBareAndProviderQualified() {
        let candidates = WeeAppModel.weeCatalogCandidateIDs(for: "qwen3:8b")

        XCTAssertEqual(candidates, ["qwen3:8b", "ollama/qwen3:8b"])
    }

    @MainActor
    func testCandidateMatchingIgnoresSurroundingWhitespace() {
        let candidates = WeeAppModel.weeCatalogCandidateIDs(for: "  gemma3:4b  ")

        XCTAssertEqual(candidates, ["gemma3:4b", "ollama/gemma3:4b"])
    }

    @MainActor
    func testBlankModelNameProducesNoCandidates() {
        XCTAssertTrue(WeeAppModel.weeCatalogCandidateIDs(for: "   ").isEmpty)
    }

    @MainActor
    func testRefreshRunsForAnAuthenticatedLocalWeeSession() {
        XCTAssertTrue(WeeAppModel.shouldRefreshWeeCatalog(
            environment: .local,
            hasAuthToken: true,
            runtime: "wee"
        ))
        XCTAssertTrue(WeeAppModel.shouldRefreshWeeCatalog(
            environment: .local,
            hasAuthToken: true,
            runtime: "  WEE "
        ))
    }

    @MainActor
    func testRefreshIsSkippedWhenItCouldNotOrShouldNotApply() {
        // A Remote window's catalog is not affected by this Mac's Ollama.
        XCTAssertFalse(WeeAppModel.shouldRefreshWeeCatalog(
            environment: .remote,
            hasAuthToken: true,
            runtime: "wee"
        ))
        // Without a token the catalog request cannot succeed.
        XCTAssertFalse(WeeAppModel.shouldRefreshWeeCatalog(
            environment: .local,
            hasAuthToken: false,
            runtime: "wee"
        ))
        // Other runtimes do not serve Ollama-backed models.
        XCTAssertFalse(WeeAppModel.shouldRefreshWeeCatalog(
            environment: .local,
            hasAuthToken: true,
            runtime: "copilot"
        ))
    }
}

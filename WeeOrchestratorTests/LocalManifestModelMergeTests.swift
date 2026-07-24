import XCTest
@testable import WeeOrchestrator

/// Issue #23: models configured for the copilot / copilot-sdk runtimes in Local
/// Settings were written to `model-manifest.json` but never reached the chat
/// model picker, because the Local API's `/models` endpoint did not report them
/// back. The client now merges the manifest it wrote as a fallback.
final class LocalManifestModelMergeTests: XCTestCase {
    @MainActor
    func testManifestModelsMissingFromTheAPIAreAddedToThePicker() {
        let apiModels = [ModelCatalogEntry(id: "gpt-4o", label: "GPT-4o", group: "Copilot")]

        let merged = WeeAppModel.mergingLocalManifestModels(
            apiModels,
            manifestModels: ["gpt-4o", "claude-sonnet-4.6", "o3-mini"],
            runtime: "copilot"
        )

        XCTAssertEqual(merged.map(\.id), ["gpt-4o", "claude-sonnet-4.6", "o3-mini"])
        XCTAssertEqual(merged.map(\.group), ["Copilot", "Local Settings", "Local Settings"])
    }

    @MainActor
    func testAPIReportedModelsAreNeverDuplicatedOrReordered() {
        let apiModels = [
            ModelCatalogEntry(id: "a", label: "A", group: "Copilot"),
            ModelCatalogEntry(id: "b", label: "B", group: "Copilot")
        ]

        let merged = WeeAppModel.mergingLocalManifestModels(
            apiModels,
            manifestModels: ["b", "a"],
            runtime: "copilot-sdk"
        )

        XCTAssertEqual(merged.map(\.id), ["a", "b"])
    }

    @MainActor
    func testBlankManifestEntriesAreIgnored() {
        let merged = WeeAppModel.mergingLocalManifestModels(
            [],
            manifestModels: ["  ", "", "  real-model  "],
            runtime: "copilot"
        )

        XCTAssertEqual(merged.map(\.id), ["real-model"])
    }

    /// The Wee catalog is discovered dynamically from Ollama and OpenRouter and
    /// is deliberately absent from the manifest, so it must never be augmented
    /// from that file.
    @MainActor
    func testWeeCatalogIsNotAugmentedFromTheManifest() {
        let apiModels = [ModelCatalogEntry(id: "ollama/qwen3:8b", label: "Qwen 3", group: "Wee Native (Ollama)")]

        let merged = WeeAppModel.mergingLocalManifestModels(
            apiModels,
            manifestModels: ["something-stale"],
            runtime: "wee"
        )

        XCTAssertEqual(merged.map(\.id), ["ollama/qwen3:8b"])
    }
}

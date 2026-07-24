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

    /// Issue #46: the Local API's `/models?runtime=codex` returns exactly one
    /// entry — `default` — while the same endpoint returns the full manifest
    /// list for copilot. The nine Codex models recorded in
    /// `model-manifest.json` were therefore invisible in the picker.
    ///
    /// This reproduces that exact payload shape.
    @MainActor
    func test_issue_46_configuredCodexModelsAppearWhenTheAPIReturnsOnlyDefault() {
        // Exactly what the API reports for the codex runtime today.
        let apiModels = [ModelCatalogEntry(id: "default", label: "default", group: "Codex CLI")]

        // Exactly what model-manifest.json records for codex.
        let configured = [
            "gpt-5.6", "gpt-5.6-luna", "gpt-5.6-terral", "gpt-5.6-sol",
            "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-5.2"
        ]

        let merged = WeeAppModel.mergingLocalManifestModels(
            apiModels,
            manifestModels: configured,
            runtime: "codex"
        )

        XCTAssertEqual(merged.count, 10, "Expected the API default plus all nine configured Codex models")
        XCTAssertEqual(merged.first?.id, "default", "The API-reported default must stay first")
        for model in configured {
            XCTAssertTrue(
                merged.contains { $0.id == model },
                "Configured Codex model \(model) is missing from the picker"
            )
        }
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

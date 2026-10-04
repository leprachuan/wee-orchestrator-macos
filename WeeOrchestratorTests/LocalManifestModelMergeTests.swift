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

    /// A prior runtime's response may complete after the user switches the
    /// picker to a new runtime. The stale result must be discarded.
    @MainActor
    func testStaleRuntimeCatalogIsNotAppliedAfterRuntimeChanges() {
        XCTAssertFalse(
            WeeAppModel.shouldApplyModelCatalog(
                requestedRuntime: "codex",
                selectedRuntime: "claude"
            )
        )
        XCTAssertTrue(
            WeeAppModel.shouldApplyModelCatalog(
                requestedRuntime: " Claude ",
                selectedRuntime: "claude"
            )
        )
    }
    @MainActor
    func testIssue516FavoritesGroupPrecedesAllProvidersAndPreservesOrder() {
        let catalog = [
            ModelCatalogEntry(id: "ollama/a", label: "Local", group: "Ollama"),
            ModelCatalogEntry(id: "openrouter/b", label: "Cloud", group: "Favorites"),
            ModelCatalogEntry(id: "ollama/c", label: "Local favorite", group: "Favorites"),
            ModelCatalogEntry(id: "openrouter/d", label: "Other cloud", group: "AAA Cloud")
        ]
        let groups = WeeAppModel.modelGroups(catalog)
        XCTAssertEqual(groups.map(\.key), ["Favorites", "AAA Cloud", "Ollama"])
        XCTAssertEqual(groups[0].value.map(\.id), ["openrouter/b", "ollama/c"])
        XCTAssertEqual(catalog[0].group, "Ollama")
    }

    func testIssue516FavoritesSettingsDecodeAndEncodeQualifiedIDs() throws {
        let data = Data(#"{"version":1,"models":["openrouter/openai/gpt-4.1-mini","ollama/qwen3:8b"]}"#.utf8)
        let config = try JSONDecoder().decode(ModelFavoritesConfig.self, from: data)
        XCTAssertEqual(config.models, ["openrouter/openai/gpt-4.1-mini", "ollama/qwen3:8b"])
        XCTAssertEqual(try JSONDecoder().decode(ModelFavoritesConfig.self, from: JSONEncoder().encode(config)), config)
    }

}

final class AutonomyContractTests: XCTestCase {
    func testRuntimeModelSettingsPreserveIndependentSelections() throws {
        let data = Data(#"{"routine_runtime":"codex","routine_model":"gpt-6-luna","escalation_runtime":"claude-sdk","escalation_models":["sonnet"],"max_requests_per_run":3,"max_output_tokens":1024,"daily_requests":20,"daily_token_budget":40000}"#.utf8)
        var config = try JSONDecoder().decode(AutonomyModelConfig.self, from: data)
        XCTAssertEqual(config.routineRuntime, "codex")
        XCTAssertEqual(config.routineModel, "gpt-6-luna")
        config.dailyRequests = 12
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String:Any])
        XCTAssertEqual(object["routine_runtime"] as? String, "codex")
        XCTAssertEqual(object["routine_model"] as? String, "gpt-6-luna")
        XCTAssertEqual(object["escalation_runtime"] as? String, "claude-sdk")
        XCTAssertEqual(object["daily_requests"] as? Int, 12)
    }

    func testSharedApprovalContractBindsReviewedFingerprint() throws {
        let data = Data(#"{"requests":[{"id":"request-1","responsibility":"review","fingerprint":"immutable-reviewed-hash","status":"pending","preview":{"summary":"Review report"},"scope":{"agent":"wee-dev","operation":"file.write","host":"dev","resource":"/workspace/report.md"}}]}"#.utf8)
        let list = try JSONDecoder().decode(AutonomyApprovalList.self, from: data)
        let approval = try XCTUnwrap(list.requests.first)
        XCTAssertEqual(approval.fingerprint, "immutable-reviewed-hash")
        XCTAssertEqual(approval.scope.resource, "/workspace/report.md")
        let body = try JSONEncoder().encode(AutonomyDecision(decision: "approve_always", fingerprint: approval.fingerprint))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String:String])
        XCTAssertEqual(object["fingerprint"], approval.fingerprint)
    }
    func testRuleContractPreservesRevocationAndPrefixScope() throws {
        let data = Data(#"{"enabled":false,"rules":[{"id":"rule-1","agent":"a","operation":"file.read","host":"dev","resource":"/workspace","decision":"allow","enabled":false,"path_prefix":true}]}"#.utf8)
        let policy = try JSONDecoder().decode(AutonomyRules.self, from: data)
        XCTAssertFalse(policy.enabled)
        XCTAssertFalse(policy.rules[0].enabled)
        XCTAssertTrue(policy.rules[0].pathPrefix)
        XCTAssertFalse(AutonomyScope(agent:"a",operation:"shell.execute",host:"dev",resource:"shell").supportsPermanentGrant)
    }
}

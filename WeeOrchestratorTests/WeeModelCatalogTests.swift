import XCTest
@testable import WeeOrchestrator

final class WeeModelCatalogTests: XCTestCase {
    /// Issue #425: provider-qualified IDs must survive API decoding unchanged so
    /// the selected endpoint can be resolved by the Wee runtime.
    func testQualifiedOllamaAndOpenRouterModelsDecodeWithoutLosingProvider() throws {
        let payload = #"""
        {
          "runtime": "wee",
          "models": [
            {"id":"ollama/qwen3:8b","label":"Qwen 3","group":"Wee Native (Ollama)"},
            {"id":"openrouter/anthropic/claude-sonnet-4","label":"Claude Sonnet","group":"OpenRouter"}
          ],
          "error": null
        }
        """#.data(using: .utf8)!

        let response = try JSONDecoder().decode(ModelCatalogResponse.self, from: payload)

        XCTAssertEqual(response.models.map(\.id), [
            "ollama/qwen3:8b",
            "openrouter/anthropic/claude-sonnet-4"
        ])
        XCTAssertEqual(response.models.map(\.group), [
            "Wee Native (Ollama)",
            "OpenRouter"
        ])
    }
}

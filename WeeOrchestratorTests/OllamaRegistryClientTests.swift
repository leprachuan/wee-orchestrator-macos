import XCTest
@testable import WeeOrchestrator

final class OllamaRegistryClientTests: XCTestCase {
    /// Issue #392: the Local Models registry search needs to parse ollama.com's
    /// server-rendered search results page to find candidate model families.
    func test_issue_392_parseBaseModelNamesFromSearchPage() {
        let html = """
        <a href="/library/qwen3">qwen3</a>
        <a href="/library/qwen3.5">qwen3.5</a>
        <a href="/library/qwen3.6">qwen3.6</a>
        <a href="/library/qwen3.6">qwen3.6 (duplicate)</a>
        <a href="/library/qwen3-coder">qwen3-coder</a>
        """

        let names = OllamaRegistryClient.parseBaseModelNames(from: html, limit: 10)

        XCTAssertEqual(names, ["qwen3", "qwen3.5", "qwen3.6", "qwen3-coder"])
    }

    func test_issue_392_parseBaseModelNamesRespectsLimit() {
        let html = (0..<10).map { #"<a href="/library/model-\#($0)">m</a>"# }.joined(separator: "\n")

        let names = OllamaRegistryClient.parseBaseModelNames(from: html, limit: 3)

        XCTAssertEqual(names.count, 3)
    }

    /// Issue #392: only tag variants with a 64K+ context window may be surfaced to the
    /// user for download. This mirrors the row markup ollama.com/library/<model> renders
    /// per tag, e.g. "9.6GB · 128K context window · Text, Image · 3 months ago".
    func test_issue_392_parseTagVariantsEnforces64KContextWindow() {
        let html = """
        <a href="/library/gemma4:e4b" class="sm:hidden flex flex-col">
          <p>gemma4:e4b</p>
          <p class="flex text-neutral-500">9.6GB · 128K context window · Text, Image · 3 months ago</p>
        </a>
        <a href="/library/gemma4:tiny" class="sm:hidden flex flex-col">
          <p>gemma4:tiny</p>
          <p class="flex text-neutral-500">1.1GB · 32K context window · Text · 3 months ago</p>
        </a>
        <a href="/library/gemma4:26b" class="sm:hidden flex flex-col">
          <p>gemma4:26b</p>
          <p class="flex text-neutral-500">18GB · 256K context window · Text, Image · 3 months ago</p>
        </a>
        """

        let variants = OllamaRegistryClient.parseTagVariants(from: html, baseName: "gemma4")

        XCTAssertEqual(Set(variants.map(\.tag)), ["e4b", "26b"])
        XCTAssertFalse(variants.contains { $0.tag == "tiny" })
        XCTAssertTrue(variants.allSatisfy { $0.contextWindow >= OllamaRegistryClient.minimumContextWindow })
    }

    func test_issue_392_parseTagVariantsDedupesAndReadsSize() {
        let html = """
        <a href="/library/qwen3.6:27b">
          <p>qwen3.6:27b</p>
          <p class="flex text-neutral-500">17GB · 256K context window · Text, Image · 2 months ago</p>
        </a>
        <div class="hidden group px-4 py-3 sm:grid sm:grid-cols-12">
          <a href="/library/qwen3.6:27b">qwen3.6:27b</a>
          <p x-test-model-tag-size class="col-span-2 text-neutral-500">17GB</p>
          <p class="col-span-2 text-neutral-500">256K</p>
        </div>
        """

        let variants = OllamaRegistryClient.parseTagVariants(from: html, baseName: "qwen3.6")

        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(variants.first?.tag, "27b")
        XCTAssertEqual(variants.first?.contextWindow, 256_000)
        XCTAssertEqual(variants.first?.sizeGB, 17)
        XCTAssertEqual(variants.first?.fullTag, "qwen3.6:27b")
    }
}

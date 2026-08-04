import XCTest
@testable import WeeOrchestrator

final class MarkdownTextMediaTests: XCTestCase {
    private let localBase = URL(string: "http://127.0.0.1:8001")!
    private let remoteBase = URL(string: "https://100.124.186.75:8000")!

    // MARK: - URL resolution (issue 52 root cause: relative /ai-media paths never resolved)

    func test_issue_52_relativeAiMediaPathResolvesAgainstLocalBaseURL() {
        let resolved = MarkdownText.resolveMediaURL("/ai-media/9040a535/chart.png", relativeTo: localBase)
        XCTAssertEqual(resolved?.absoluteString, "http://127.0.0.1:8001/ai-media/9040a535/chart.png")
    }

    func test_issue_52_relativeAiMediaPathResolvesAgainstRemoteBaseURL() {
        let resolved = MarkdownText.resolveMediaURL("/ai-media/9040a535/chart.png", relativeTo: remoteBase)
        XCTAssertEqual(resolved?.absoluteString, "https://100.124.186.75:8000/ai-media/9040a535/chart.png")
    }

    func test_issue_52_absoluteHTTPSURLIsPreservedUnchanged() {
        let resolved = MarkdownText.resolveMediaURL("https://example.com/chart.png", relativeTo: localBase)
        XCTAssertEqual(resolved?.absoluteString, "https://example.com/chart.png")
    }

    func test_issue_52_relativePathWithNoBaseURLFailsToResolve() {
        XCTAssertNil(MarkdownText.resolveMediaURL("/ai-media/9040a535/chart.png", relativeTo: nil))
    }

    func test_issue_52_emptyURLStringFailsToResolve() {
        XCTAssertNil(MarkdownText.resolveMediaURL("", relativeTo: localBase))
    }

    // MARK: - End-to-end block parsing

    func test_issue_52_relativeMarkdownImageRendersAsResolvedImageBlock() {
        let markdown = "![Age-matched financial percentile charts](/ai-media/9040a535/chart.png)"
        let blocks = MarkdownText(markdown, baseURL: localBase).debugBlocks()
        XCTAssertEqual(blocks, [
            .image(alt: "Age-matched financial percentile charts", url: "http://127.0.0.1:8001/ai-media/9040a535/chart.png")
        ])
    }

    func test_issue_52_relativeMarkdownImageWithoutBaseURLFallsBackToUnsupportedChip() {
        let markdown = "![Chart](/ai-media/9040a535/chart.png)"
        let blocks = MarkdownText(markdown, baseURL: nil).debugBlocks()
        XCTAssertEqual(blocks, [.unsupportedVisualization(file: "Chart")])
    }

    // MARK: - Codex inline visualization directive (issue 52: must never render as raw literal text)

    func test_issue_52_codexInlineVisDirectiveDoesNotRenderAsLiteralText() {
        let markdown = #"::codex-inline-vis{file="age-40-financial-percentiles.html"}"#
        let blocks = MarkdownText(markdown, baseURL: localBase).debugBlocks()
        XCTAssertEqual(blocks, [.unsupportedVisualization(file: "age-40-financial-percentiles.html")])
        for block in blocks {
            if case .paragraph(let text) = block {
                XCTFail("Directive leaked into a literal paragraph: \(text)")
            }
        }
    }

    func test_issue_52_codexInlineVisDirectiveMixedWithSurroundingText() {
        let markdown = "Here is your chart:\n\n::codex-inline-vis{file=\"chart.html\"}\n\nLet me know if you'd like changes."
        let blocks = MarkdownText(markdown, baseURL: localBase).debugBlocks()
        XCTAssertEqual(blocks, [
            .paragraph("Here is your chart:"),
            .unsupportedVisualization(file: "chart.html"),
            .paragraph("Let me know if you'd like changes."),
        ])
    }
}

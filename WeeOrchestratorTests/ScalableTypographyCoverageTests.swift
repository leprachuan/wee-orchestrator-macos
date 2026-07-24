import XCTest
import SwiftUI
@testable import WeeOrchestrator

/// Issue #27: the Appearance text-size control drives `dynamicTypeSize`, but
/// the desktop UI is built from fixed-point fonts that ignore it. All app
/// typography must therefore go through the `weeFont` layer, which multiplies
/// its point size by `WeeTypography.scale(for:)`.
///
/// These tests scan the shipping sources rather than a rendered view because
/// the failure mode is silent: a plain `.font(...)` renders perfectly, it just
/// stops responding to the setting. A source guard is what actually keeps the
/// conversion from eroding as new views are added.
final class ScalableTypographyCoverageTests: XCTestCase {
    /// The only legitimate `.font(` in the app is inside `weeFont`'s own
    /// implementation, which is what applies the scale.
    private static let allowedRawFontFile = "WeeTheme.swift"

    private var sourceFiles: [URL] {
        get throws {
            let repositoryRoot = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // WeeOrchestratorTests
                .deletingLastPathComponent()   // repository root
            let sourceRoot = repositoryRoot.appendingPathComponent("WeeOrchestrator")

            let enumerator = try XCTUnwrap(
                FileManager.default.enumerator(at: sourceRoot, includingPropertiesForKeys: nil),
                "Could not enumerate \(sourceRoot.path)"
            )

            return enumerator
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
        }
    }

    func testNoAppViewBypassesTheScalableTypographyLayer() throws {
        let files = try sourceFiles
        XCTAssertFalse(files.isEmpty, "Expected to find Swift sources to scan")

        var offenders: [String] = []
        for file in files where file.lastPathComponent != Self.allowedRawFontFile {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.components(separatedBy: .newlines).enumerated()
            where line.contains(".font(") && !line.contains(".weeFont(") {
                offenders.append("\(file.lastPathComponent):\(index + 1) — \(line.trimmingCharacters(in: .whitespaces))")
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "These call sites ignore the Appearance text-size setting. Use .weeFont(...) instead:\n"
                + offenders.joined(separator: "\n")
        )
    }

    /// Guards the one permitted exception, so the allowance stays exactly as
    /// narrow as it is today.
    func testOnlyTheTypographyLayerItselfAppliesARawFont() throws {
        let themeFile = try XCTUnwrap(
            try sourceFiles.first { $0.lastPathComponent == Self.allowedRawFontFile }
        )
        let contents = try String(contentsOf: themeFile, encoding: .utf8)

        let rawFontLines = contents
            .components(separatedBy: .newlines)
            .filter { $0.contains(".font(") && !$0.contains(".weeFont(") }

        XCTAssertEqual(rawFontLines.count, 1, "Expected exactly one raw font application in \(Self.allowedRawFontFile)")
        XCTAssertTrue(
            try XCTUnwrap(rawFontLines.first).contains(".font(.system("),
            "The permitted raw font must be the scaled system font inside weeFont"
        )
    }

    /// Every semantic style must resolve to a real point size, so converting a
    /// `.font(.caption)` style call to `.weeFont(.caption)` can never silently
    /// collapse to zero.
    func testEverySemanticStyleHasAPositiveScaledPointSize() {
        let styles: [Font.TextStyle] = [
            .largeTitle, .title, .title2, .title3, .headline,
            .subheadline, .body, .callout, .footnote, .caption, .caption2
        ]

        for style in styles {
            let base = WeeTypography.pointSize(for: style)
            XCTAssertGreaterThan(base, 0, "\(style) has no point size")
            XCTAssertGreaterThan(
                base * WeeTypography.scale(for: .xxxLarge),
                base * WeeTypography.scale(for: .xSmall),
                "\(style) does not respond to the text-size setting"
            )
        }
    }
}

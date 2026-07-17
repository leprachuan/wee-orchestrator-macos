import XCTest
@testable import WeeOrchestrator

@MainActor
final class AppTextSizeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "wee.appTextSize")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "wee.appTextSize")
        super.tearDown()
    }

    /// Issue #17: text size must be adjustable in both directions and clamp
    /// at the ends of the supported step range instead of wrapping or
    /// producing an out-of-range DynamicTypeSize.
    func test_textSizeClampsAtBothEnds() {
        let model = WeeAppModel()
        XCTAssertEqual(model.textSizeLabel, "Default")
        XCTAssertTrue(model.canIncreaseTextSize)
        XCTAssertTrue(model.canDecreaseTextSize)

        for _ in 0..<10 { model.increaseTextSize() }
        XCTAssertEqual(model.appTextSize, WeeAppModel.textSizeSteps.last)
        XCTAssertFalse(model.canIncreaseTextSize)

        for _ in 0..<10 { model.decreaseTextSize() }
        XCTAssertEqual(model.appTextSize, WeeAppModel.textSizeSteps.first)
        XCTAssertFalse(model.canDecreaseTextSize)

        model.resetTextSize()
        XCTAssertEqual(model.textSizeLabel, "Default")
    }

    func test_textSizePersistsAcrossModelInstances() {
        UserDefaults.standard.removeObject(forKey: "wee.appTextSize")
        let model = WeeAppModel()
        model.increaseTextSize()
        model.increaseTextSize()
        let expected = model.appTextSize

        let reloaded = WeeAppModel()
        XCTAssertEqual(reloaded.appTextSize, expected)
    }

    func testTypographyScaleChangesAtEachSupportedExtreme() {
        XCTAssertEqual(WeeTypography.scale(for: .large), 1.0, accuracy: 0.001)
        XCTAssertLessThan(WeeTypography.scale(for: .xSmall), 1.0)
        XCTAssertGreaterThan(WeeTypography.scale(for: .xxxLarge), 1.0)
        XCTAssertGreaterThan(
            WeeTypography.scale(for: .xxxLarge),
            WeeTypography.scale(for: .xLarge)
        )
    }

    func testSemanticTextStylesUseTheSharedTextSizeScale() {
        let bodySize = WeeTypography.pointSize(for: .body)
        let captionSize = WeeTypography.pointSize(for: .caption)

        XCTAssertGreaterThan(bodySize * WeeTypography.scale(for: .xxxLarge), bodySize)
        XCTAssertLessThan(captionSize * WeeTypography.scale(for: .xSmall), captionSize)
    }
}

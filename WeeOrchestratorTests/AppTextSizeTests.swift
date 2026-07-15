import XCTest
@testable import WeeOrchestrator

@MainActor
final class AppTextSizeTests: XCTestCase {
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
}

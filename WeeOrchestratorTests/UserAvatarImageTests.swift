import XCTest
@testable import WeeOrchestrator

@MainActor
final class UserAvatarImageTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "wee.userAvatarImagePath")
        super.tearDown()
    }

    /// Issue #25: a picked avatar image must be copied into app-owned
    /// storage (not just referenced by the picker's URL, which can be a
    /// temporary/security-scoped location) and be loadable afterward.
    func test_settingAvatarCopiesFileAndPersistsPath() throws {
        let model = WeeAppModel()
        XCTAssertNil(model.userAvatarImage)

        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("avatar-\(UUID().uuidString).png")
        let pixel = NSImage(size: NSSize(width: 4, height: 4))
        pixel.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        pixel.unlockFocus()
        guard let tiffData = pixel.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not construct a test PNG")
            return
        }
        try pngData.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        model.setUserAvatarImage(from: sourceURL)

        XCTAssertFalse(model.userAvatarImagePath.isEmpty)
        XCTAssertNotEqual(model.userAvatarImagePath, sourceURL.path, "must be copied, not reference the original URL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.userAvatarImagePath))
        XCTAssertNotNil(model.userAvatarImage)

        model.clearUserAvatarImage()
        XCTAssertTrue(model.userAvatarImagePath.isEmpty)
        XCTAssertNil(model.userAvatarImage)
    }
}

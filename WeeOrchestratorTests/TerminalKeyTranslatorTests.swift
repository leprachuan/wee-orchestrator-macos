import XCTest
@testable import WeeOrchestrator

final class TerminalKeyTranslatorTests: XCTestCase {
    // MARK: - special keys

    func test_returnMapsToCarriageReturn() {
        let input = TerminalKeyInput(characters: "\r", key: "return", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\r")
    }

    func test_escapeMapsToEscapeByte() {
        let input = TerminalKeyInput(characters: "", key: "escape", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\u{1B}")
    }

    func test_tabMapsToTabByte() {
        let input = TerminalKeyInput(characters: "\t", key: "tab", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\t")
    }

    func test_deleteMapsToDelByte() {
        let input = TerminalKeyInput(characters: "", key: "delete", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\u{7F}")
    }

    func test_upArrowMapsToAnsiSequence() {
        let input = TerminalKeyInput(characters: "", key: "upArrow", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\u{1B}[A")
    }

    func test_downArrowMapsToAnsiSequence() {
        let input = TerminalKeyInput(characters: "", key: "downArrow", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\u{1B}[B")
    }

    func test_rightArrowMapsToAnsiSequence() {
        let input = TerminalKeyInput(characters: "", key: "rightArrow", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\u{1B}[C")
    }

    func test_leftArrowMapsToAnsiSequence() {
        let input = TerminalKeyInput(characters: "", key: "leftArrow", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\u{1B}[D")
    }

    // MARK: - plain characters

    func test_plainCharacterPassesThrough() {
        let input = TerminalKeyInput(characters: "a", key: "", hasControlModifier: false)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "a")
    }

    func test_emptyCharactersWithNoKeyReturnsNil() {
        let input = TerminalKeyInput(characters: "", key: "", hasControlModifier: false)
        XCTAssertNil(TerminalKeyTranslator.bytes(for: input))
    }

    // MARK: - control modifier

    func test_controlCMapsToSigintByte() {
        let input = TerminalKeyInput(characters: "c", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), String(Character(UnicodeScalar(3))))
    }

    func test_controlDMapsToEofByte() {
        let input = TerminalKeyInput(characters: "d", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), String(Character(UnicodeScalar(4))))
    }

    func test_controlAMapsToFirstControlByte() {
        let input = TerminalKeyInput(characters: "a", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), String(Character(UnicodeScalar(1))))
    }

    func test_controlZMapsToLastControlByte() {
        let input = TerminalKeyInput(characters: "z", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), String(Character(UnicodeScalar(26))))
    }

    func test_controlUppercaseLetterMapsSameAsLowercase() {
        let input = TerminalKeyInput(characters: "C", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), String(Character(UnicodeScalar(3))))
    }

    func test_controlModifierWithMultiCharacterStringFallsBackToPassthrough() {
        // Guards against, e.g., a composed/dead-key sequence resolving to more
        // than one scalar -- should not be treated as a control byte.
        let input = TerminalKeyInput(characters: "ab", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "ab")
    }

    func test_controlModifierWithNonLetterFallsBackToPassthrough() {
        let input = TerminalKeyInput(characters: "1", key: "", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "1")
    }

    func test_controlModifierWithEmptyCharactersReturnsNil() {
        let input = TerminalKeyInput(characters: "", key: "", hasControlModifier: true)
        XCTAssertNil(TerminalKeyTranslator.bytes(for: input))
    }

    // MARK: - special keys ignore control modifier state

    func test_specialKeyTakesPrecedenceOverControlModifier() {
        let input = TerminalKeyInput(characters: "", key: "return", hasControlModifier: true)
        XCTAssertEqual(TerminalKeyTranslator.bytes(for: input), "\r")
    }
}

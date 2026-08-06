import Foundation

/// A keystroke captured from the terminal surface, reduced to plain values
/// so the byte-translation logic below is unit-testable without SwiftUI's
/// `KeyPress` type in the loop (the View layer constructs this from a real
/// `KeyPress` and passes it here -- see NativeShellPanel in ShellSession.swift).
struct TerminalKeyInput: Equatable {
    /// The literal characters the system resolved for this keystroke (already
    /// accounts for the current keyboard layout, dead keys, etc.) -- used for
    /// ordinary printable input.
    let characters: String
    /// A name for a non-printable key ("return", "escape", "tab", "delete",
    /// "upArrow", "downArrow", "leftArrow", "rightArrow"), or "" for anything
    /// that should be treated as printable input via `characters` instead.
    let key: String
    let hasControlModifier: Bool
}

/// Translates a captured keystroke into the exact bytes to write to the PTY
/// (issue #61: the terminal surface itself is now the input, not a separate
/// line-buffered command field -- so every keystroke, not just a submitted
/// line, needs a byte sequence).
enum TerminalKeyTranslator {
    static func bytes(for input: TerminalKeyInput) -> String? {
        switch input.key {
        case "return": return "\r"
        case "escape": return "\u{1B}"
        case "tab": return "\t"
        case "delete": return "\u{7F}"
        case "upArrow": return "\u{1B}[A"
        case "downArrow": return "\u{1B}[B"
        case "rightArrow": return "\u{1B}[C"
        case "leftArrow": return "\u{1B}[D"
        default:
            if input.hasControlModifier, let controlByte = controlByte(for: input.characters) {
                return String(controlByte)
            }
            return input.characters.isEmpty ? nil : input.characters
        }
    }

    /// Ctrl+<letter> maps to the byte range 0x01-0x1A (Ctrl-A through Ctrl-Z),
    /// the standard terminal control-character encoding -- Ctrl-C (0x03,
    /// SIGINT) and Ctrl-D (0x04, EOF) are the two everyone recognizes, but
    /// every letter maps the same way.
    private static func controlByte(for characters: String) -> Character? {
        guard let scalar = characters.unicodeScalars.first, characters.unicodeScalars.count == 1 else { return nil }
        let lowered = Character(scalar).lowercased()
        guard let asciiValue = lowered.unicodeScalars.first?.value,
              asciiValue >= 97, asciiValue <= 122 else { return nil }
        return Character(UnicodeScalar(asciiValue - 96)!)
    }
}

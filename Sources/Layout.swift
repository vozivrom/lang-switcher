import Foundation
import Carbon

/// A physical key press: hardware keycode plus whether Shift was held.
struct KeyStroke: Hashable {
    let code: UInt16
    let shift: Bool
}

/// One character resolved to the key that produces it, or kept verbatim when
/// the source layout can't produce it. `original` is the fallback used if a
/// target layout has nothing on that key.
enum Token {
    case key(KeyStroke, original: Character)
    case literal(Character)
}

extension Token: Equatable {
    /// Compares what was typed, ignoring which layout rendered it — the same
    /// word reached through different layouts must compare equal.
    static func == (lhs: Token, rhs: Token) -> Bool {
        switch (lhs, rhs) {
        case let (.key(a, _), .key(b, _)): return a == b
        case let (.literal(a), .literal(b)): return a == b
        default: return false
        }
    }
}

/// An installed keyboard layout. The character/key mapping is read from the
/// system with UCKeyTranslate rather than hardcoded, so every layout the user
/// has installed works without us maintaining a table for it.
struct Layout: Identifiable, Equatable {
    let id: String            // input source id, e.g. "com.apple.keylayout.Russian"
    let name: String          // localized, e.g. "Russian"
    let languages: [String]   // e.g. ["ru", "bg"]
    let charToStroke: [Character: KeyStroke]
    let strokeToChar: [KeyStroke: Character]

    static func == (lhs: Layout, rhs: Layout) -> Bool { lhs.id == rhs.id }
}

/// Discovers the keyboard layouts installed on this Mac.
enum KeyboardLayouts {

    /// Keycodes covering the alphanumeric block — everything a word is made of.
    private static let keyCodes: ClosedRange<UInt16> = 0...50

    private static var cached: [Layout] = []

    static var all: [Layout] {
        if cached.isEmpty { cached = discover() }
        return cached
    }

    static func layout(id: String) -> Layout? { all.first { $0.id == id } }

    /// Re-reads the installed layouts, picking up any the user just added.
    static func refresh() { cached = discover() }

    private static func discover() -> [Layout] {
        let filter = [kTISPropertyInputSourceCategory as String:
                        kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              let sources = list as? [TISInputSource] else { return [] }

        return sources.compactMap { source in
            // Input methods (Chinese, Japanese, …) have no key layout data and
            // aren't something we can remap positionally.
            guard let id = property(source, kTISPropertyInputSourceID) as? String,
                  let data = property(source, kTISPropertyUnicodeKeyLayoutData) as? Data
            else { return nil }

            let (charToStroke, strokeToChar) = buildMaps(from: data)
            guard !charToStroke.isEmpty else { return nil }

            return Layout(id: id,
                          name: property(source, kTISPropertyLocalizedName) as? String ?? id,
                          languages: property(source, kTISPropertyInputSourceLanguages) as? [String] ?? [],
                          charToStroke: charToStroke,
                          strokeToChar: strokeToChar)
        }
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> AnyObject? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Asks the OS what each key produces in this layout, with and without Shift.
    private static func buildMaps(from data: Data) -> ([Character: KeyStroke], [KeyStroke: Character]) {
        var charToStroke: [Character: KeyStroke] = [:]
        var strokeToChar: [KeyStroke: Character] = [:]

        data.withUnsafeBytes { raw in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            let keyboardType = UInt32(LMGetKbdType())

            for code in keyCodes {
                for shift in [false, true] {
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)

                    let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay),
                                                shift ? UInt32(shiftKey >> 8) : 0,
                                                keyboardType,
                                                UInt32(kUCKeyTranslateNoDeadKeysBit),
                                                &deadKeyState, chars.count, &length, &chars)

                    guard status == noErr, length == 1,
                          let character = String(utf16CodeUnits: chars, count: length).first,
                          !character.isWhitespace
                    else { continue }

                    let stroke = KeyStroke(code: code, shift: shift)
                    if strokeToChar[stroke] == nil { strokeToChar[stroke] = character }
                    if charToStroke[character] == nil { charToStroke[character] = stroke }
                }
            }
        }
        return (charToStroke, strokeToChar)
    }
}

import Foundation

/// Positional remapping between US-QWERTY and Russian ЙЦУКЕН layouts.
///
/// The app fixes "typed in the wrong layout" mistakes: e.g. someone meant to
/// type `house` but had the Russian layout active and produced `рщгыу`.
/// Conversion is per-character based on physical key position; characters that
/// have no mapping (digits, spaces, etc.) are left untouched.
enum LayoutConverter {

    // US character (the glyph that key produces on a US layout) -> Russian glyph.
    private static let enLower = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,./`")
    private static let ruLower = Array("йцукенгшщзхъфывапролджэячсмитьбю.ё")

    private static let enUpper = Array("QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~")
    private static let ruUpper = Array("ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё")

    /// Latin glyph -> Cyrillic glyph.
    private static let enToRu: [Character: Character] = buildMap(from: enLower + enUpper,
                                                                 to: ruLower + ruUpper)
    /// Cyrillic glyph -> Latin glyph (inverse).
    private static let ruToEn: [Character: Character] = buildMap(from: ruLower + ruUpper,
                                                                 to: enLower + enUpper)

    private static func buildMap(from: [Character], to: [Character]) -> [Character: Character] {
        var map: [Character: Character] = [:]
        for (a, b) in zip(from, to) { map[a] = b }
        return map
    }

    /// Returns true if the text contains at least one Cyrillic letter.
    private static func containsCyrillic(_ text: String) -> Bool {
        for ch in text where ("а"..."я").contains(ch) || ("А"..."Я").contains(ch)
            || ch == "ё" || ch == "Ё" {
            return true
        }
        return false
    }

    /// Auto-detects direction and remaps. Cyrillic present -> RU→EN, else EN→RU.
    static func convert(_ text: String) -> String {
        let map = containsCyrillic(text) ? ruToEn : enToRu
        return String(text.map { map[$0] ?? $0 })
    }

    /// The keyboard language the user should switch to after converting `text`:
    /// if the input was Cyrillic we produced English, so they want "en"; otherwise "ru".
    static func targetLanguage(for text: String) -> String {
        return containsCyrillic(text) ? "en" : "ru"
    }
}

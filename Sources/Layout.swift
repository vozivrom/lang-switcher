import Foundation

/// A keyboard layout described as a positional mapping against US-QWERTY.
/// `forward` maps a US key glyph -> this layout's glyph; `reverse` is the
/// inverse (this layout's glyph -> US key glyph). Characters not in the table
/// (digits, space, …) are left untouched by callers.
struct Layout: Identifiable, Equatable {
    let id: String        // "en", "ru", "uk"
    let name: String      // "English", "Russian", "Ukrainian"
    let langCode: String  // for switching the system input source
    let forward: [Character: Character]
    let reverse: [Character: Character]

    static func == (lhs: Layout, rhs: Layout) -> Bool { lhs.id == rhs.id }
}

/// The US-QWERTY reference rows that every layout is aligned against.
private let usLower = "qwertyuiop[]asdfghjkl;'zxcvbnm,./`"
private let usUpper = "QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~"

private func makeLayout(id: String, name: String, langCode: String,
                        lower: String, upper: String) -> Layout {
    let keys = Array(usLower) + Array(usUpper)
    let glyphs = Array(lower) + Array(upper)
    precondition(keys.count == glyphs.count, "layout \(id) row length mismatch")
    var forward: [Character: Character] = [:]
    var reverse: [Character: Character] = [:]
    for (key, glyph) in zip(keys, glyphs) {
        forward[key] = glyph
        reverse[glyph] = key
    }
    return Layout(id: id, name: name, langCode: langCode, forward: forward, reverse: reverse)
}

/// The layouts the user can add to their cycle. Add a new entry here (with its
/// two aligned rows) to support another language.
enum LayoutCatalog {
    static let english = makeLayout(
        id: "en", name: "English", langCode: "en",
        lower: "qwertyuiop[]asdfghjkl;'zxcvbnm,./`",
        upper: "QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?~")

    static let russian = makeLayout(
        id: "ru", name: "Russian", langCode: "ru",
        lower: "йцукенгшщзхъфывапролджэячсмитьбю.ё",
        upper: "ЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё")

    static let ukrainian = makeLayout(
        id: "uk", name: "Ukrainian", langCode: "uk",
        lower: "йцукенгшщзхїфівапролджєячсмитьбю.'",
        upper: "ЙЦУКЕНГШЩЗХЇФІВАПРОЛДЖЄЯЧСМИТЬБЮ,'")

    static let all: [Layout] = [english, russian, ukrainian]
    static let byID: [String: Layout] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

import Foundation

// Layouts are built by hand rather than read from the machine, so the results
// don't depend on which keyboards happen to be installed — the CI runner has
// only U.S., this Mac has three.

var failures = 0
var checks = 0

func check(_ passed: Bool, _ label: String) {
    checks += 1
    if passed {
        print("  ok    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    checks += 1
    if actual == expected {
        print("  ok    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)\n          expected: \(expected)\n          actual:   \(actual)")
    }
}

func section(_ name: String) { print("\n\(name)") }

/// Builds a layout from aligned characters, one per keycode.
func makeLayout(id: String, name: String, characters: String) -> Layout {
    var charToStroke: [Character: KeyStroke] = [:]
    var strokeToChar: [KeyStroke: Character] = [:]
    for (index, character) in characters.enumerated() {
        let stroke = KeyStroke(code: UInt16(index), shift: false)
        charToStroke[character] = stroke
        strokeToChar[stroke] = character
    }
    return Layout(id: id, name: name, languages: [id],
                  charToStroke: charToStroke, strokeToChar: strokeToChar)
}

// Same keys, different glyphs. `twin` renders identically to `latin` — the case
// that used to stall the cycle (Russian and Ukrainian share most keys).
let latin = makeLayout(id: "latin", name: "Latin", characters: "abcde;2")
let cyrillic = makeLayout(id: "cyrillic", name: "Cyrillic", characters: "фисвуж3")
let twin = makeLayout(id: "twin", name: "Twin", characters: "abcde;2")

// MARK: - Conversion

section("conversion")
do {
    let cycle = [latin, cyrillic]
    let step = CycleEngine.next(text: "abc", cycle: cycle, state: nil, now: 0)
    checkEqual(step?.text, "фис", "latin converts to cyrillic")
    checkEqual(step?.layoutID, "cyrillic", "keyboard follows the text")

    let back = CycleEngine.next(text: "фис", cycle: cycle, state: nil, now: 0)
    checkEqual(back?.text, "abc", "cyrillic converts back")

    // Characters no layout can produce must survive untouched.
    let mixed = CycleEngine.next(text: "ab#", cycle: cycle, state: nil, now: 0)
    checkEqual(mixed?.text, "фи#", "unmapped characters pass through")

    // Punctuation converts like anything else; this is the "d;m" case.
    let punctuation = CycleEngine.next(text: "ab;2", cycle: cycle, state: nil, now: 0)
    checkEqual(punctuation?.text, "фиж3", "punctuation and digits convert")
}

// MARK: - Whitespace

section("whitespace")
do {
    let cycle = [latin, cyrillic]
    checkEqual(CycleEngine.next(text: " abc", cycle: cycle, state: nil, now: 0)?.text,
               " фис", "leading space kept")
    checkEqual(CycleEngine.next(text: "abc ", cycle: cycle, state: nil, now: 0)?.text,
               "фис ", "trailing space kept")
    check(CycleEngine.next(text: "   ", cycle: cycle, state: nil, now: 0) == nil,
          "whitespace-only input does nothing")
    check(CycleEngine.next(text: "", cycle: cycle, state: nil, now: 0) == nil,
          "empty input does nothing")
    check(CycleEngine.next(text: "abc", cycle: [latin], state: nil, now: 0) == nil,
          "a single layout cannot cycle")
}

// MARK: - Cycling

section("cycling")
do {
    let cycle = [latin, cyrillic, twin]
    var state: CycleState?
    var text = "abc"
    var visited: [String] = []
    for step in 0..<3 {
        guard let result = CycleEngine.next(text: text, cycle: cycle, state: state, now: Double(step)) else {
            break
        }
        visited.append(result.layoutID)
        text = result.text
        state = result.state
    }
    checkEqual(visited, ["cyrillic", "twin", "latin"], "advances one layout per press")
    checkEqual(text, "abc", "a full cycle returns the original text")
}

do {
    // A layout that renders identically must still be stepped through, so the
    // keyboard switches even though the letters don't change.
    let cycle = [latin, twin, cyrillic]
    let step = CycleEngine.next(text: "abc", cycle: cycle, state: nil, now: 0)
    checkEqual(step?.text, "abc", "identical layout leaves text alone")
    checkEqual(step?.layoutID, "twin", "but still advances the keyboard")
}

// MARK: - Continuation

section("continuation")
do {
    let cycle = [latin, cyrillic, twin]
    let first = CycleEngine.next(text: "abc", cycle: cycle, state: nil, now: 0)!
    let second = CycleEngine.next(text: first.text, cycle: cycle, state: first.state, now: 1)
    checkEqual(second?.layoutID, "twin", "continues from where it left off")

    // Re-selecting rarely returns the identical string; spacing must not reset it.
    let spaced = CycleEngine.next(text: " " + first.text, cycle: cycle, state: first.state, now: 1)
    checkEqual(spaced?.layoutID, "twin", "re-selection with a space still continues")

    // Past the window it starts fresh, so detection picks the layout again.
    let expired = CycleEngine.next(text: first.text, cycle: cycle, state: first.state,
                                   now: CycleEngine.continuationWindow + 5)
    checkEqual(expired?.layoutID, "twin", "expired state falls back to detection")

    // Editing the layout list must invalidate the stored index.
    let shorter = CycleEngine.next(text: first.text, cycle: [latin, cyrillic],
                                   state: first.state, now: 1)
    checkEqual(shorter?.layoutID, "latin", "changing the cycle restarts detection")
}

// MARK: - Detection

section("detection")
do {
    let cycle = [latin, cyrillic]
    checkEqual(CycleEngine.next(text: "abcde", cycle: cycle, state: nil, now: 0)?.layoutID,
               "cyrillic", "latin text detected as latin")
    checkEqual(CycleEngine.next(text: "фисву", cycle: cycle, state: nil, now: 0)?.layoutID,
               "latin", "cyrillic text detected as cyrillic")
    // Mostly-latin text should still be read as latin.
    checkEqual(CycleEngine.next(text: "abcф", cycle: cycle, state: nil, now: 0)?.layoutID,
               "cyrillic", "detection uses the best match, not the first character")
}

// MARK: - Settings

section("settings")
do {
    let settings = Settings.shared
    let installed = KeyboardLayouts.all.map(\.id)

    if installed.count >= 2 {
        settings.layoutIDs = installed
        settings.add("does.not.exist")
        checkEqual(settings.layoutIDs, installed, "unknown layout ids are refused")

        settings.add(installed[0])
        checkEqual(settings.layoutIDs, installed, "layouts cannot be added twice")

        settings.layoutIDs = Array(installed.prefix(2))
        settings.remove(installed[0])
        checkEqual(settings.layoutIDs.count, 2, "removal stops at the minimum")
        check(!settings.canRemove, "canRemove is false at the minimum")

        settings.layoutIDs = installed
        settings.layoutIDs.append("gone.from.system")
        settings.pruneMissingLayouts()
        checkEqual(settings.layoutIDs, installed, "uninstalled layouts are pruned")
    } else {
        print("  skip  layout-dependent settings tests (need 2+ installed)")
    }

    settings.layoutIDs = ["a", "b", "c"]
    settings.move(from: IndexSet(integer: 2), to: 0)
    checkEqual(settings.layoutIDs, ["c", "a", "b"], "move to the front")

    settings.layoutIDs = ["a", "b", "c"]
    settings.move(from: IndexSet(integer: 0), to: 3)
    checkEqual(settings.layoutIDs, ["b", "c", "a"], "move to the end")

    settings.layoutIDs = ["a", "b", "c"]
    settings.move(from: IndexSet(integer: 5), to: 0)
    checkEqual(settings.layoutIDs, ["a", "b", "c"], "out-of-range move is ignored")
}

// MARK: - Hotkeys

section("hotkeys")
do {
    checkEqual(Set(HotkeyModifier.allCases.map(\.rawValue)),
               ["shift", "command", "option", "control"], "all modifiers offered")
    let codes = HotkeyModifier.allCases.flatMap { Array($0.keyCodes) }
    checkEqual(codes.count, Set(codes).count, "no keycode is shared between modifiers")
    for modifier in HotkeyModifier.allCases {
        checkEqual(modifier.keyCodes.count, 2, "\(modifier.name) covers left and right keys")
    }
}

// MARK: - Installed layouts

section("installed layouts")
do {
    let all = KeyboardLayouts.all
    check(!all.isEmpty, "at least one layout is discovered")
    for layout in all {
        check(!layout.charToStroke.isEmpty, "\(layout.name) has a character map")
        // The two maps must be inverses of each other or conversion round-trips break.
        let consistent = layout.charToStroke.allSatisfy { character, stroke in
            layout.strokeToChar[stroke] == character
        }
        check(consistent, "\(layout.name) maps are consistent both ways")
    }
}

// MARK: - Real layouts
//
// The cases above use synthetic layouts so they run anywhere. These use the
// real ones, because the interesting failures come from how actual layouts
// disagree: Czech puts letters where U.S. has digits, and punctuation moves
// around. Skipped when a layout isn't installed — CI only has U.S.

section("real layouts")

func layout(_ name: String) -> Layout? {
    KeyboardLayouts.layout(id: "com.apple.keylayout." + name)
}

func converts(_ text: String, from: Layout, to: Layout) -> String {
    CycleEngine.render(CycleEngine.tokenize(text, layout: from), layout: to)
}

if let us = layout("US"), let czech = layout("Czech") {
    // Czech's unshifted number row is letters, so digits are where the two
    // layouts differ most.
    checkEqual(converts("2", from: us, to: czech), "ě", "digit becomes a letter in Czech")
    checkEqual(converts("1234567890", from: us, to: czech), "+ěščřžýáíé",
               "the whole number row maps to Czech letters")
    checkEqual(converts("ě", from: czech, to: us), "2", "Czech letter back to digit")

    // Punctuation moves too — this is the ";" that produced the "abz;2" bug.
    checkEqual(converts(";", from: us, to: czech), "ů", "semicolon becomes ů")
    checkEqual(converts("ů", from: czech, to: us), ";", "Czech ů back to semicolon")
    checkEqual(converts("[]", from: us, to: czech), "ú)", "brackets move as well")

    // QWERTY vs QWERTZ.
    checkEqual(converts("z", from: us, to: czech), "y", "z and y are swapped")
    checkEqual(converts("y", from: us, to: czech), "z", "in both directions")

    // Letters that sit on the same key in both layouts must survive untouched.
    checkEqual(converts("hello", from: us, to: czech), "hello",
               "shared letters are unchanged")

    // Shifted keys travel the same route: Czech's number row gives digits with
    // shift, which is the inverse of the unshifted case above.
    checkEqual(converts("@", from: us, to: czech), "2", "shifted digit row in Czech")
    checkEqual(converts("!", from: us, to: czech), "1", "shift+1 becomes a digit")
    checkEqual(converts("ABZ", from: us, to: czech), "ABY", "capitals keep the z/y swap")
    checkEqual(converts("Hello", from: us, to: czech), "Hello", "mixed case unchanged")

    // The exact string that was converting to "*2" before the selection fix.
    checkEqual(converts("abz;2", from: us, to: czech), "abyůě",
               "mixed letters, punctuation and digits")
    checkEqual(converts("abyůě", from: czech, to: us), "abz;2", "Czech round trips")
}
else {
    print("  skip  U.S. and Czech needed")
}

if let us = layout("US"), let russian = layout("Russian") {
    checkEqual(converts("house", from: us, to: russian), "рщгыу", "latin to cyrillic")
    checkEqual(converts("рщгыу", from: russian, to: us), "house", "cyrillic to latin")
    checkEqual(converts("привет", from: russian, to: us), "ghbdtn",
               "a real word converts to the keys it was typed with")

    // Punctuation again: the "d;m" case.
    checkEqual(converts(";", from: us, to: russian), "ж", "semicolon becomes ж")
    checkEqual(converts("d;m", from: us, to: russian), "вжь", "punctuation inside a word")
    checkEqual(converts("вжь", from: russian, to: us), "d;m", "Russian round trips")

    // Case is preserved because shift is part of the keystroke, not the layout.
    checkEqual(converts("House", from: us, to: russian), "Рщгыу", "capitals convert")
    checkEqual(converts("Привет", from: russian, to: us), "Ghbdtn", "and back, case intact")
    checkEqual(converts("РЩГЫУ", from: russian, to: us), "HOUSE", "all caps")

    // Trailing punctuation converts as well, since it is a key like any other.
    checkEqual(converts("hello,", from: us, to: russian), "руддщб",
               "trailing punctuation converts")
}
else {
    print("  skip  U.S. and Russian needed")
}

print("\n\(checks - failures)/\(checks) passed")
if failures > 0 {
    print("\(failures) FAILED")
    exit(1)
}

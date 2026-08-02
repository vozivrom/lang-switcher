import Foundation

/// Remembers the last switch so consecutive double-shifts advance through the
/// cycle deterministically, even when two layouts share the same script
/// (e.g. Russian and Ukrainian are both Cyrillic and can't be told apart from
/// the glyphs alone).
struct CycleState {
    let keystrokes: String        // canonical US-key representation of the text
    let index: Int                // index in the cycle of the text we last wrote
    let writtenText: String       // exactly what we pasted
    let timestamp: CFTimeInterval
    let signature: String         // the cycle this index refers to
}

/// Reinterprets text across an ordered list of keyboard layouts.
enum CycleEngine {

    /// How long after a switch a further double-shift still counts as continuing
    /// the same cycle rather than starting fresh.
    static let continuationWindow: CFTimeInterval = 8.0

    /// Produces the next step in the cycle, or nil if there's nothing to do.
    static func next(text: String, cycle: [Layout],
                     state: CycleState?, now: CFTimeInterval)
        -> (text: String, langCode: String, state: CycleState)? {

        guard cycle.count >= 2, !text.isEmpty else { return nil }

        // Selecting the previous word can hand us surrounding whitespace
        // (" house"). Cycle only the word itself and put the spacing back, so
        // repeated switches don't glue words together.
        let (leading, core, trailing) = split(text)
        guard !core.isEmpty else { return nil }

        // Editing the language list invalidates any in-flight cycle, since the
        // stored index would otherwise refer to a different layout.
        let signature = cycle.map(\.id).joined(separator: ",")

        let keystrokes: String
        let sourceIndex: Int
        if let s = state, s.signature == signature, s.index < cycle.count,
           now - s.timestamp <= continuationWindow,
           isContinuation(core: core, state: s, cycle: cycle) {
            // Continuation: keep cycling the same physical keystrokes.
            keystrokes = s.keystrokes
            sourceIndex = s.index
        } else {
            // Fresh start: guess which layout the text is currently in.
            sourceIndex = detectSourceIndex(text: core, cycle: cycle)
            keystrokes = reverse(core, layout: cycle[sourceIndex])
        }

        // Always advance exactly one step, even when the next layout renders
        // identically (Russian and Ukrainian differ in only a few keys, so
        // "привет" looks the same in both). The visible text may not change,
        // but the system keyboard still switches, which is the point.
        let targetIndex = (sourceIndex + 1) % cycle.count
        let target = cycle[targetIndex]
        let newCore = forward(keystrokes, layout: target)

        let newState = CycleState(keystrokes: keystrokes, index: targetIndex,
                                  writtenText: newCore, timestamp: now,
                                  signature: signature)
        return (leading + newCore + trailing, target.langCode, newState)
    }

    /// Whether `core` is still the text we last wrote, so the cycle continues
    /// instead of restarting. Re-selecting a word rarely returns a byte-identical
    /// string, so also accept text that maps back to the same keystrokes through
    /// the layout we last wrote in — that identifies the word regardless of how
    /// the app reported the selection.
    private static func isContinuation(core: String, state: CycleState, cycle: [Layout]) -> Bool {
        if state.writtenText == core { return true }
        return reverse(core, layout: cycle[state.index]) == state.keystrokes
    }

    /// Splits text into leading whitespace, the text itself, and trailing whitespace.
    private static func split(_ text: String) -> (String, String, String) {
        let chars = Array(text)
        var start = 0
        while start < chars.count, chars[start].isWhitespace { start += 1 }
        var end = chars.count
        while end > start, chars[end - 1].isWhitespace { end -= 1 }
        return (String(chars[0..<start]), String(chars[start..<end]), String(chars[end...]))
    }

    static func reverse(_ text: String, layout: Layout) -> String {
        String(text.map { layout.reverse[$0] ?? $0 })
    }

    static func forward(_ keystrokes: String, layout: Layout) -> String {
        String(keystrokes.map { layout.forward[$0] ?? $0 })
    }

    // Letters unique to one Cyrillic layout, used to disambiguate on a fresh start.
    private static let ukSignature: Set<Character> = ["і", "ї", "є", "ґ", "І", "Ї", "Є", "Ґ"]
    private static let ruSignature: Set<Character> = ["ы", "э", "ъ", "ё", "Ы", "Э", "Ъ", "Ё"]

    private static func detectSourceIndex(text: String, cycle: [Layout]) -> Int {
        func index(of id: String) -> Int? { cycle.firstIndex { $0.id == id } }

        if text.contains(where: { ukSignature.contains($0) }), let i = index(of: "uk") { return i }
        if text.contains(where: { ruSignature.contains($0) }), let i = index(of: "ru") { return i }

        let hasCyrillic = text.contains {
            ("а"..."я").contains($0) || ("А"..."Я").contains($0)
                || ukSignature.contains($0) || ruSignature.contains($0)
        }
        if hasCyrillic {
            if let i = cycle.firstIndex(where: { $0.id != "en" }) { return i }
        } else if let i = index(of: "en") {
            return i
        }
        return 0
    }
}

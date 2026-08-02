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

        // Editing the language list invalidates any in-flight cycle, since the
        // stored index would otherwise refer to a different layout.
        let signature = cycle.map(\.id).joined(separator: ",")

        let keystrokes: String
        let sourceIndex: Int
        if let s = state, s.signature == signature, s.index < cycle.count,
           now - s.timestamp <= continuationWindow,
           s.writtenText == text || s.writtenText.trimmedEquals(text) {
            // Continuation: keep cycling the same physical keystrokes.
            keystrokes = s.keystrokes
            sourceIndex = s.index
        } else {
            // Fresh start: guess which layout the text is currently in.
            sourceIndex = detectSourceIndex(text: text, cycle: cycle)
            keystrokes = reverse(text, layout: cycle[sourceIndex])
        }

        let targetIndex = (sourceIndex + 1) % cycle.count
        let target = cycle[targetIndex]
        let newText = forward(keystrokes, layout: target)
        guard newText != text else { return nil }

        let newState = CycleState(keystrokes: keystrokes, index: targetIndex,
                                  writtenText: newText, timestamp: now,
                                  signature: signature)
        return (newText, target.langCode, newState)
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

private extension String {
    func trimmedEquals(_ other: String) -> Bool {
        let set = CharacterSet.whitespacesAndNewlines
        return trimmingCharacters(in: set) == other.trimmingCharacters(in: set)
    }
}

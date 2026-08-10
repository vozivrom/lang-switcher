import Foundation
import QuartzCore

/// Remembers the last switch so consecutive double-shifts advance through the
/// cycle deterministically, even when two layouts render the same text
/// (Russian and Ukrainian differ in only a few keys).
struct CycleState {
    let tokens: [Token]           // what was physically typed
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
    /// - Parameter activeLayoutID: the keyboard in use, which breaks ties when
    ///   several layouts could have produced the text.
    static func next(text: String, cycle: [Layout],
                     state: CycleState?, now: CFTimeInterval,
                     activeLayoutID: String? = nil)
        -> (text: String, layoutID: String, state: CycleState)? {

        guard cycle.count >= 2, !text.isEmpty else { return nil }

        // Selecting the previous word can hand us surrounding whitespace
        // (" house"). Cycle only the word itself and put the spacing back, so
        // repeated switches don't glue words together.
        let (leading, core, trailing) = split(text)
        guard !core.isEmpty else { return nil }

        // Editing the layout list invalidates any in-flight cycle, since the
        // stored index would otherwise refer to a different layout.
        let signature = cycle.map(\.id).joined(separator: ",")

        let tokens: [Token]
        let sourceIndex: Int
        if let s = state, s.signature == signature, s.index < cycle.count,
           now - s.timestamp <= continuationWindow,
           isContinuation(core: core, state: s, cycle: cycle) {
            // Continuation: keep cycling the same physical keystrokes.
            tokens = s.tokens
            sourceIndex = s.index
        } else {
            // Fresh start: guess which layout the text is currently in.
            sourceIndex = detectSourceIndex(text: core, cycle: cycle, active: activeLayoutID)
            tokens = tokenize(core, layout: cycle[sourceIndex])
        }

        // Always advance exactly one step, even when the next layout renders
        // identically. The visible text may not change, but the system keyboard
        // still switches, which is the point.
        let targetIndex = (sourceIndex + 1) % cycle.count
        let target = cycle[targetIndex]
        let newCore = render(tokens, layout: target)

        let newState = CycleState(tokens: tokens, index: targetIndex,
                                  writtenText: newCore, timestamp: now,
                                  signature: signature)
        return (leading + newCore + trailing, target.id, newState)
    }

    /// Resolves text to the keys that produce it in `layout`.
    static func tokenize(_ text: String, layout: Layout) -> [Token] {
        text.map { character in
            if let stroke = layout.charToStroke[character] {
                return .key(stroke, original: character)
            }
            return .literal(character)
        }
    }

    /// Renders keys as the characters `layout` puts on them.
    static func render(_ tokens: [Token], layout: Layout) -> String {
        String(tokens.map { token in
            switch token {
            case let .key(stroke, original):
                return layout.strokeToChar[stroke] ?? original
            case let .literal(character):
                return character
            }
        })
    }

    /// Whether `core` is still the text we last wrote, so the cycle continues
    /// instead of restarting. Re-selecting a word rarely returns a byte-identical
    /// string, so also accept text that resolves to the same keystrokes through
    /// the layout we last wrote in.
    private static func isContinuation(core: String, state: CycleState, cycle: [Layout]) -> Bool {
        if state.writtenText == core { return true }
        return tokenize(core, layout: cycle[state.index]) == state.tokens
    }

    /// Picks the layout that can produce the most of this text. Beats hardcoded
    /// alphabet checks and works for any layout the user installs.
    ///
    /// Scores alone can't separate layouts that share an alphabet: "yvf" is
    /// equally typeable on U.S. and Czech, but which one was used decides
    /// whether it becomes "нма" or "яма". The keyboard that is active now is
    /// the one the text was just typed on, so it wins ties — while a layout
    /// that genuinely explains more of the text still wins outright.
    private static func detectSourceIndex(text: String, cycle: [Layout], active: String?) -> Int {
        let scores = cycle.map { layout in
            text.reduce(0) { $0 + (layout.charToStroke[$1] != nil ? 1 : 0) }
        }
        guard let best = scores.max() else { return 0 }

        if let active = active,
           let index = cycle.firstIndex(where: { $0.id == active }),
           scores[index] == best {
            return index
        }
        return scores.firstIndex(of: best) ?? 0
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
}

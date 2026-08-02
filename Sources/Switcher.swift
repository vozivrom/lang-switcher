import Cocoa
import CoreGraphics
import QuartzCore

/// Grabs the relevant text (selection, or the previous word / whole field
/// depending on scope), advances it one step through the layout cycle, and
/// pastes the result back in place.
enum Switcher {

    private static let keyA: CGKeyCode = 0
    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9
    private static let keyLeftArrow: CGKeyCode = 123
    private static let keyRightArrow: CGKeyCode = 124

    private static let source = CGEventSource(stateID: .combinedSessionState)

    /// Stamped on every event we post so the detector can tell our synthetic
    /// keystrokes (the Shift in ⇧⌥←) from the user's own.
    static let syntheticTag: Int64 = 0x1A_9C_5E_11

    /// Persisted across calls so consecutive double-shifts keep cycling.
    private static var lastState: CycleState?

    /// Runs the full grab → cycle → paste cycle. Call off the main thread so the
    /// waits don't block the event tap's run loop.
    static func run(cycle: [Layout], scope: Scope) {
        guard cycle.count >= 2 else { return }

        // The user has just tapped Shift twice and may still be holding it.
        // Posting ⌘C while a physical modifier is down delivers ⇧⌘C to the app,
        // which silently does something else (or nothing).
        waitForModifiersToClear()

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        guard let original = grabText(scope: scope), !original.isEmpty else {
            restore(pasteboard, items: saved)
            return
        }

        guard let result = CycleEngine.next(text: original, cycle: cycle,
                                            state: lastState,
                                            now: CACurrentMediaTime()) else {
            restore(pasteboard, items: saved)
            return
        }

        // Paste the converted text over the selection.
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        usleep(30_000)
        postKey(keyV, flags: .maskCommand)

        // Give the app time to actually read the pasteboard before putting the
        // user's clipboard back, otherwise it can paste the old contents.
        usleep(180_000)
        restore(pasteboard, items: saved)
        lastState = result.state

        // Switch the system keyboard to the target layout.
        let layoutID = result.layoutID
        DispatchQueue.main.async {
            InputSource.select(id: layoutID)
        }
    }

    // MARK: - Getting the text

    /// Returns the text to convert, left selected so pasting replaces it:
    /// the current selection if there is one, otherwise the previous word or
    /// the whole field per `scope`.
    private static func grabText(scope: Scope) -> String? {
        if let selection = TextAccess.selectedText() {
            // The app exposes its text, so we know whether something is selected.
            if !selection.isEmpty { return selection }
            selectFallbackRange(scope: scope)
            if let widened = TextAccess.selectedText(), !widened.isEmpty { return widened }
            return copySelection()
        }

        // Accessibility isn't available here: fall back to probing with ⌘C.
        if let copied = copySelection() { return copied }
        selectFallbackRange(scope: scope)
        return copySelection()
    }

    /// Selects what to convert when nothing is selected.
    private static func selectFallbackRange(scope: Scope) {
        switch scope {
        case .word:
            // ⇧⌥← stops at punctuation, so "d;m" would only give "m". Select
            // back to whitespace instead — that's the run the user typed.
            if TextAccess.selectPreviousRun() { return }
            if extendSelectionToWhitespace() { return }
            postKey(keyLeftArrow, flags: [.maskShift, .maskAlternate])
        case .text:
            postKey(keyA, flags: .maskCommand)
        }
        usleep(60_000)
    }

    /// Grows the selection one character at a time until it reaches whitespace
    /// or the start of the field.
    ///
    /// Chromium-based apps (VS Code, Slack, Discord) refuse to have their
    /// selection range set through Accessibility, but they do report the
    /// selected text — so we walk left with ⇧← and watch what gets selected.
    ///
    /// - Returns: false if the app doesn't report selections either, so the
    ///   caller can fall back to word-wise selection.
    private static func extendSelectionToWhitespace(limit: Int = 64) -> Bool {
        var selected = ""
        for _ in 0..<limit {
            postKey(keyLeftArrow, flags: .maskShift)
            usleep(12_000)

            guard let current = TextAccess.selectedText() else { return false }
            if current == selected { break }        // start of the field
            if let first = current.first, first.isWhitespace {
                // Overshot into the previous word; hand the character back.
                postKey(keyRightArrow, flags: .maskShift)
                usleep(12_000)
                break
            }
            selected = current
        }
        return !selected.isEmpty
    }

    /// Presses ⌘C and waits for the pasteboard to actually change, rather than
    /// sleeping a fixed amount and hoping. Returns nil if nothing was copied.
    private static func copySelection(timeout: Double = 0.3) -> String? {
        let pasteboard = NSPasteboard.general
        let before = pasteboard.changeCount
        postKey(keyC, flags: .maskCommand)

        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            if pasteboard.changeCount != before {
                return pasteboard.string(forType: .string)
            }
            usleep(10_000)
        }
        return nil
    }

    // MARK: - Event helpers

    /// Blocks until no modifier keys are physically held, so our synthetic
    /// keystrokes aren't merged with the user's.
    private static func waitForModifiersToClear(timeout: Double = 0.6) {
        let watched: CGEventFlags = [.maskShift, .maskCommand, .maskAlternate, .maskControl]
        let deadline = CACurrentMediaTime() + timeout
        while CACurrentMediaTime() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(watched).isEmpty { return }
            usleep(10_000)
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.setIntegerValueField(.eventSourceUserData, value: syntheticTag)
            up.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Clipboard preservation

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}

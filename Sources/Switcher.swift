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
    private static let keyDelete: CGKeyCode = 51

    private static let source = CGEventSource(stateID: .combinedSessionState)

    /// Stamped on every event we post so the detector can tell our synthetic
    /// keystrokes (the Shift in ⇧⌥←) from the user's own.
    static let syntheticTag: Int64 = 0x1A_9C_5E_11

    /// Persisted across calls so consecutive double-shifts keep cycling.
    private static var lastState: CycleState?

    /// Runs the full grab → cycle → paste cycle. Call off the main thread so the
    /// waits don't block the event tap's run loop.
    /// - Parameter activeLayoutID: read by the caller on the main thread. The
    ///   Text Input Source APIs assert they are called there, and this runs on a
    ///   background queue.
    static func run(cycle: [Layout], scope: Scope, activeLayoutID: String?) {
        guard cycle.count >= 2 else { return }

        // The user has just tapped Shift twice and may still be holding it.
        // Posting ⌘C while a physical modifier is down delivers ⇧⌘C to the app,
        // which silently does something else (or nothing).
        waitForModifiersToClear()

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        guard let grab = grabText(scope: scope), !grab.text.isEmpty else {
            restore(pasteboard, items: saved)
            return
        }
        let original = grab.text

        guard let result = CycleEngine.next(text: original, cycle: cycle,
                                            state: lastState,
                                            now: CACurrentMediaTime(),
                                            activeLayoutID: activeLayoutID) else {
            restore(pasteboard, items: saved)
            return
        }


        // Paste the converted text over the selection.
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        usleep(30_000)

        // A terminal ignores the selection when pasting, so take the characters
        // out first. Deleting exactly what we grabbed keeps the two consistent:
        // whatever gets replaced is what was read.
        if TerminalApps.isFrontmost {
            for _ in 0..<original.count {
                postKey(keyDelete, flags: [])
            }
            usleep(40_000)
        }

        postKey(keyV, flags: .maskCommand)

        // Give the app time to actually read the pasteboard before putting the
        // user's clipboard back, otherwise it can paste the old contents.
        usleep(180_000)
        restore(pasteboard, items: saved)
        lastState = result.state

        // Leave text the user selected under a selection, so pressing again
        // carries on cycling the same run instead of falling back to the last
        // word. Terminals have no selection to restore.
        if grab.wasUserSelection, !TerminalApps.isFrontmost {
            reselect(result.text)
            // Restoring the selection prompts the field to reassert its own
            // layout. Let that happen before setting ours, so the keyboard
            // changes once — switching first means fighting it back afterwards,
            // and macOS's layout badge then shows one of the intermediate steps.
            usleep(220_000)
        }

        // Switch the system keyboard to the target layout, after the selection
        // has settled — restoring it can make the field reassert its own layout.
        let layoutID = result.layoutID
        DispatchQueue.main.async {
            InputSource.selectPersistently(id: layoutID)
        }
    }

    // MARK: - Getting the text

    /// Text to convert, and whether the user had selected it themselves.
    ///
    /// The distinction matters afterwards: text the user selected is put back
    /// under a selection so it can be converted again, while a last-word fix is
    /// left unselected so the next keystroke doesn't wipe it.
    private struct Grab {
        let text: String
        let wasUserSelection: Bool
    }

    /// Returns the text to convert, left selected so pasting replaces it:
    /// the current selection if there is one, otherwise the previous word or
    /// the whole field per `scope`.
    private static func grabText(scope: Scope) -> Grab? {
        if let selection = TextAccess.selectedText() {
            // The app exposes its text, so we know whether something is selected.
            if !selection.isEmpty { return Grab(text: selection, wasUserSelection: true) }
            selectFallbackRange(scope: scope)
            if let widened = TextAccess.selectedText(), !widened.isEmpty {
                return Grab(text: widened, wasUserSelection: false)
            }
            return copySelection().map { Grab(text: $0, wasUserSelection: false) }
        }

        // Accessibility isn't available here: fall back to probing with ⌘C.
        // Anything it returns before we widen the range was already selected.
        if let copied = copySelection() { return Grab(text: copied, wasUserSelection: true) }
        selectFallbackRange(scope: scope)
        return copySelection().map { Grab(text: $0, wasUserSelection: false) }
    }

    /// Selects what to convert when nothing is selected.
    private static func selectFallbackRange(scope: Scope) {
        switch scope {
        case .word:
            // ⇧⌥← stops at punctuation, so "d;m" would only give "m". Select
            // back to whitespace instead — that's the run the user typed.
            if TextAccess.selectPreviousRun() { return }
            if extendSelectionToWhitespace() { return }
            if selectRunViaLine() { return }
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

    /// Puts a selection back over the text just pasted.
    ///
    /// Accessibility does it in one step. Where that isn't available the only
    /// option is walking back a character at a time, which is capped — past a
    /// few hundred keystrokes the delay is worse than losing the selection.
    private static func reselect(_ text: String) {
        if TextAccess.selectPreceding(text.utf16.count) { return }

        let steps = text.count
        guard steps > 0, steps <= reselectKeystrokeLimit else { return }
        for _ in 0..<steps {
            postKey(keyLeftArrow, flags: .maskShift)
        }
    }

    private static let reselectKeystrokeLimit = 300

    /// Selects the run before the caret without using Accessibility at all.
    ///
    /// VS Code and other Electron apps only expose their text to Accessibility
    /// when assistive tech is detected, so the strategies above get nothing
    /// back. This works purely with keystrokes and the clipboard: select to the
    /// start of the line, read it, put the caret back, then select exactly the
    /// characters after the last whitespace.
    private static func selectRunViaLine() -> Bool {
        postKey(keyLeftArrow, flags: [.maskShift, .maskCommand])
        usleep(50_000)

        guard let line = copySelection(), !line.isEmpty else { return false }

        // Right arrow collapses the selection to its trailing end, i.e. back to
        // where the caret started.
        postKey(keyRightArrow, flags: [])
        usleep(30_000)

        var length = 0
        for character in line.reversed() {
            if character.isWhitespace { break }
            length += 1
        }
        guard length > 0 else { return false }

        for _ in 0..<length {
            postKey(keyLeftArrow, flags: .maskShift)
        }
        usleep(50_000)
        return true
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

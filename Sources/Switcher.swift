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

    private static let source = CGEventSource(stateID: .combinedSessionState)

    /// Persisted across calls so consecutive double-shifts keep cycling.
    private static var lastState: CycleState?

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    /// Runs the full grab → cycle → paste cycle. Call off the main thread so the
    /// short sleeps don't block the event tap's run loop.
    static func run(cycle: [Layout], scope: Scope) {
        guard cycle.count >= 2 else { return }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(pasteboard)

        // 1. Try to copy an existing selection.
        let before = pasteboard.changeCount
        postKey(keyC, flags: .maskCommand)
        usleep(90_000)

        var text: String?
        if pasteboard.changeCount != before {
            text = pasteboard.string(forType: .string)
        } else {
            // 2. Nothing selected: select per scope, then copy.
            switch scope {
            case .word:
                postKey(keyLeftArrow, flags: [.maskShift, .maskAlternate])
            case .text:
                postKey(keyA, flags: .maskCommand)
            }
            usleep(40_000)
            let beforeSelect = pasteboard.changeCount
            postKey(keyC, flags: .maskCommand)
            usleep(90_000)
            if pasteboard.changeCount != beforeSelect {
                text = pasteboard.string(forType: .string)
            }
        }

        guard let original = text, !original.isEmpty else {
            restore(pasteboard, items: saved)
            return
        }

        let now = CACurrentMediaTime()
        guard let result = CycleEngine.next(text: original, cycle: cycle,
                                            state: lastState, now: now) else {
            restore(pasteboard, items: saved)
            return
        }

        // 3. Paste the converted text over the selection.
        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        usleep(20_000)
        postKey(keyV, flags: .maskCommand)
        usleep(120_000)

        // 4. Restore the user's clipboard and remember the new cycle position.
        restore(pasteboard, items: saved)
        lastState = result.state

        // 5. Switch the system keyboard to the target layout's language.
        let langCode = result.langCode
        DispatchQueue.main.async {
            InputSource.select(language: langCode)
        }
    }

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

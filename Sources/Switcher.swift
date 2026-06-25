import Cocoa
import CoreGraphics

/// Grabs the relevant text (current selection, or the previous word if nothing
/// is selected), remaps its layout, and pastes the result back in place.
enum Switcher {

    private static let keyC: CGKeyCode = 8
    private static let keyV: CGKeyCode = 9
    private static let keyLeftArrow: CGKeyCode = 123

    private static let source = CGEventSource(stateID: .combinedSessionState)

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

    /// Runs the full grab → convert → paste cycle. Call off the main thread so
    /// the short sleeps don't block the event tap's run loop.
    static func run() {
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
            // 2. Nothing was selected: select the previous word, then copy.
            postKey(keyLeftArrow, flags: [.maskShift, .maskAlternate])
            usleep(40_000)
            let beforeWord = pasteboard.changeCount
            postKey(keyC, flags: .maskCommand)
            usleep(90_000)
            if pasteboard.changeCount != beforeWord {
                text = pasteboard.string(forType: .string)
            }
        }

        guard let original = text, !original.isEmpty else {
            restore(pasteboard, items: saved)
            return
        }

        let converted = LayoutConverter.convert(original)
        guard converted != original else {
            restore(pasteboard, items: saved)
            return
        }

        // 3. Paste the converted text over the selection.
        pasteboard.clearContents()
        pasteboard.setString(converted, forType: .string)
        usleep(20_000)
        postKey(keyV, flags: .maskCommand)
        usleep(120_000)

        // 4. Put the user's original clipboard back.
        restore(pasteboard, items: saved)

        // 5. Switch the system keyboard to the language they meant to type in,
        //    so continued typing comes out correctly.
        let target = LayoutConverter.targetLanguage(for: original)
        DispatchQueue.main.async {
            InputSource.select(language: target)
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

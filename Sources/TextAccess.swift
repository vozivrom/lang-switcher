import Cocoa
import ApplicationServices

/// Reads and adjusts the focused text field's selection through the
/// Accessibility API.
///
/// This is more reliable than probing with ⌘C, because some apps answer a copy
/// even when the text field has no selection — Telegram, for example, copies
/// the focused chat message, which made the app convert the wrong text.
enum TextAccess {

    /// The focused element's selected text.
    /// - Returns: `nil` when the app doesn't expose its text to Accessibility
    ///   (caller should fall back to the clipboard), or an empty string when
    ///   the field is focused but nothing is selected.
    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    /// Selects everything from the caret back to the nearest whitespace.
    ///
    /// Word-wise selection (⇧⌥←) stops at punctuation, so "d;m" would yield
    /// only "m". A wrongly-typed word often contains punctuation — it is
    /// whatever those keys produce in the active layout — so the run between
    /// spaces is the unit the user means.
    ///
    /// - Returns: false if the app doesn't support this, so the caller can fall
    ///   back to keystroke-based selection.
    static func selectPreviousRun() -> Bool {
        guard let element = focusedElement(),
              let text = stringValue(of: element),
              let caret = selectedRange(of: element)
        else { return false }

        let contents = text as NSString
        var start = caret.location
        guard start >= 0, start <= contents.length else { return false }

        while start > 0, let scalar = Unicode.Scalar(contents.character(at: start - 1)),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start -= 1
        }

        let length = caret.location - start
        guard length > 0 else { return false }
        return setSelectedRange(of: element, CFRange(location: start, length: length))
    }

    // MARK: - Accessibility plumbing

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        // Don't let an unresponsive app block the hotkey.
        AXUIElementSetMessagingTimeout(system, 0.4)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success,
              let element = value,
              CFGetTypeID(element) == AXUIElementGetTypeID()
        else { return nil }
        return (element as! AXUIElement)
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            &value) == .success,
              let wrapped = value,
              CFGetTypeID(wrapped) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue((wrapped as! AXValue), .cfRange, &range) else { return nil }
        return range
    }

    private static func setSelectedRange(of element: AXUIElement, _ range: CFRange) -> Bool {
        var range = range
        guard let value = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString,
                                            value) == .success
    }
}

import Cocoa
import ApplicationServices

/// Reads the focused text field's selection through the Accessibility API.
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
}

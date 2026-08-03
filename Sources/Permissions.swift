import Cocoa
import ApplicationServices

/// Accessibility is the one grant this app needs: it covers reading the focused
/// field's text, posting keystrokes, and receiving them in the event tap.
///
/// macOS also has an Input Monitoring toggle, but it's the narrower permission
/// for apps that only observe keystrokes — holding Accessibility makes it
/// redundant, so we never ask for it.
enum Permissions {

    /// - Parameter prompt: show the system's "open System Settings" alert.
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

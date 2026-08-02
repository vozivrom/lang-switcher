import Cocoa
import ApplicationServices
import IOKit.hid

/// macOS requires two separate grants for what this app does, in two different
/// panes of System Settings, and grants one without implying the other:
///
/// - **Accessibility** — read the focused field's text and post keystrokes.
/// - **Input Monitoring** — receive key events in the CGEventTap.
///
/// Missing either one makes the hotkey silently do nothing, which is the most
/// confusing possible failure, so both are surfaced in the settings panel.
enum Permissions {

    /// - Parameter prompt: show the system's "open System Settings" alert.
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static var isInputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Shows the system prompt, once ever. Returns immediately afterwards, so
    /// it's safe to call on every launch.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static var allGranted: Bool { isAccessibilityTrusted() && isInputMonitoringGranted }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

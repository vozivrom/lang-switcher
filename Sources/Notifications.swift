import Foundation

extension Notification.Name {
    /// Posted when the settings content changes height, so the panel window can
    /// follow — its frame is fixed at open time and would otherwise clip.
    static let settingsContentResized = Notification.Name("LangSwitcherSettingsContentResized")

    /// Posted when the trigger modifier changes, so the detector can follow.
    static let hotkeyChanged = Notification.Name("LangSwitcherHotkeyChanged")

    /// Posted when update checking is switched on or off.
    static let updatePreferenceChanged = Notification.Name("LangSwitcherUpdatePreferenceChanged")
}

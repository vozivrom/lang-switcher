import Foundation
import ServiceManagement

/// Controls whether the app launches automatically at login.
enum LoginItem {
    /// Registers at login, but only from /Applications.
    ///
    /// A copy run from a build folder or a mounted DMG would otherwise register
    /// *itself*, and keep coming back at every login to compete with the
    /// installed app for the same Accessibility grant.
    static func enable() {
        guard Instance.isInstalled else { return }
        setEnabled(true)
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ on: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if on {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("LangSwitcher: login item toggle failed: \(error)")
            }
        }
    }
}

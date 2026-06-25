import Foundation
import ServiceManagement

/// Registers the app to launch automatically at login.
enum LoginItem {
    static func enable() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } catch {
                NSLog("LangSwitcher: failed to register login item: \(error)")
            }
        }
    }
}

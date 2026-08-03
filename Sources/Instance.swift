import Cocoa

/// Guards against the two ways this app ends up fighting itself.
///
/// macOS ties an Accessibility grant to a bundle id *and* a code signature. Two
/// copies sharing the id — one in /Applications, another in a build folder, a
/// mounted DMG, or the Trash — each invalidate the other's grant, so the app
/// prompts on every launch and the toggle appears to switch itself off.
enum Instance {

    /// A copy installed anywhere else can be replaced or deleted behind our
    /// back; only /Applications is stable enough to register at login or hold
    /// on to a permission.
    static var isInstalled: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    static var location: String {
        (Bundle.main.bundlePath as NSString).deletingLastPathComponent
    }

    /// Another process with our bundle id, if one is already running.
    static func alreadyRunning() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let ours = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == id && $0.processIdentifier != ours
        }
    }
}

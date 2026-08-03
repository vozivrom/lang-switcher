import Cocoa
import Carbon

/// Wires everything together: requests Accessibility access, starts the
/// double-Shift detector (retrying until permission is granted), and registers
/// the login item.
final class AppController {

    private let detector = DoubleTapDetector()
    private let statusItem = StatusItemController()
    private var permissionTimer: Timer?
    private var hotkeyObserver: NSObjectProtocol?
    private var inputSourcesObserver: NSObjectProtocol?

    func start() {
        LoginItem.enable()
        // Touch settings at launch so any migration of stored layout ids happens
        // now rather than the first time the user opens the panel.
        _ = Settings.shared.cycle
        AppLayoutMemory.shared.setEnabled(Settings.shared.rememberLayoutPerApp)
        detector.modifier = Settings.shared.hotkey

        // The installed layouts are cached, so notice when the user adds or
        // removes one in System Settings and drop any that have gone.
        inputSourcesObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { _ in
            KeyboardLayouts.refresh()
            Settings.shared.pruneMissingLayouts()
        }
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.detector.modifier = Settings.shared.hotkey
        }
        statusItem.install()

        detector.onDoubleTap = { [weak self] in
            guard let self = self else { return }
            // Read settings on the main thread (this callback runs on the main
            // run loop), then hand a snapshot to the background worker.
            let cycle = Settings.shared.cycle
            let scope = Settings.shared.scope
            self.detector.isPaused = true
            DispatchQueue.global(qos: .userInitiated).async {
                Switcher.run(cycle: cycle, scope: scope)
                DispatchQueue.main.async {
                    self.detector.isPaused = false
                }
            }
        }

        if Permissions.isAccessibilityTrusted(prompt: true), tryToListen() { return }

        // Not listening yet: poll until whatever is missing gets granted.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            guard Permissions.isAccessibilityTrusted(), self.tryToListen() else { return }
            timer.invalidate()
            self.permissionTimer = nil
        }
    }

    /// Enables the event tap.
    ///
    /// Never asks for Input Monitoring: a listen-only keyboard tap runs on
    /// Accessibility alone, and tap creation can fail transiently (right after a
    /// relaunch, say), so treating any failure as a missing permission prompts
    /// for something that isn't the problem. The panel offers it as a manual
    /// remedy instead.
    private func tryToListen() -> Bool {
        guard detector.enable() else { return false }
        AppState.shared.isListening = true
        return true
    }
}

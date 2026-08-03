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
    private var updateObserver: NSObjectProtocol?
    private var updateTimer: Timer?

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
        updateObserver = NotificationCenter.default.addObserver(
            forName: .updatePreferenceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.scheduleUpdateChecks()
        }
        scheduleUpdateChecks()

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

        // Check quietly first. At login the permission often hasn't resolved
        // yet, and asking straight away puts up a prompt for something the user
        // already granted — which is worse than waiting a moment.
        if Permissions.isAccessibilityTrusted(), tryToListen() { return }

        var promptAfter: Date? = Date().addingTimeInterval(promptGracePeriod)
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }

            if Permissions.isAccessibilityTrusted(), self.tryToListen() {
                timer.invalidate()
                self.permissionTimer = nil
                return
            }

            // Still nothing after the grace period, so it really is missing:
            // ask once, then leave the panel to explain it.
            if let deadline = promptAfter, Date() >= deadline {
                promptAfter = nil
                _ = Permissions.isAccessibilityTrusted(prompt: true)
            }
        }
    }

    /// How long to wait for a granted permission to show up before prompting.
    private let promptGracePeriod: TimeInterval = 5

    /// Checks on launch and daily while the setting is on.
    private func scheduleUpdateChecks() {
        updateTimer?.invalidate()
        updateTimer = nil

        guard Settings.shared.checkForUpdates else {
            AppState.shared.availableUpdate = nil
            return
        }

        let check: () -> Void = {
            UpdateChecker.check { version in
                AppState.shared.availableUpdate = version
                guard let version = version else { return }
                // Installing verifies the download against our own signature and
                // refuses anything that doesn't match, so this can't be used to
                // push a foreign build onto the user.
                AppState.shared.updateStatus = "Installing \(version)…"
                Updater.install(version: version) { result in
                    if case .failure(let error) = result {
                        AppState.shared.updateStatus = error.localizedDescription
                    }
                }
            }
        }
        check()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { _ in
            check()
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

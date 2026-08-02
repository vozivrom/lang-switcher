import Cocoa

/// Wires everything together: requests Accessibility access, starts the
/// double-Shift detector (retrying until permission is granted), and registers
/// the login item.
final class AppController {

    private let detector = DoubleShiftDetector()
    private let statusItem = StatusItemController()
    private var permissionTimer: Timer?

    func start() {
        LoginItem.enable()
        // Touch settings at launch so any migration of stored layout ids happens
        // now rather than the first time the user opens the panel.
        _ = Settings.shared.cycle
        statusItem.install()

        detector.onDoubleShift = { [weak self] in
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

    /// Enables the event tap, asking for Input Monitoring only if it fails.
    ///
    /// Accessibility alone is usually enough for a listen-only keyboard tap, so
    /// requesting Input Monitoring up front would prompt for something most
    /// users don't need — and leave a permanent warning if they dismissed it.
    private func tryToListen() -> Bool {
        if detector.enable() {
            AppState.shared.isListening = true
            return true
        }
        if !Permissions.isInputMonitoringGranted {
            Permissions.requestInputMonitoring()
        }
        return false
    }
}

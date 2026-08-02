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

        if isTrusted(prompt: true) {
            detector.enable()
        } else {
            // Permission not granted yet: poll until the user enables it.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                guard let self = self else { return }
                if self.isTrusted(prompt: false), self.detector.enable() {
                    timer.invalidate()
                    self.permissionTimer = nil
                }
            }
        }
    }

    private func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }
}

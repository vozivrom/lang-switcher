import Cocoa
import Carbon

/// Remembers which keyboard layout was last used in each application and
/// restores it when that app comes back to the front — so Telegram can stay on
/// Russian while the editor stays on English, without switching by hand.
///
/// Layouts are recorded whenever the input source changes, so a double-shift
/// conversion updates the memory for the current app too.
final class AppLayoutMemory {
    static let shared = AppLayoutMemory()

    private let defaults = UserDefaults.standard
    private let storageKey = "layoutByApp"

    private var workspaceObserver: NSObjectProtocol?
    private var inputSourceObserver: NSObjectProtocol?

    /// Set while we're applying a remembered layout, so restoring doesn't get
    /// recorded as if the user had chosen it.
    private var isRestoring = false

    /// The app we're switching away from, whose layout we record on the way out.
    private var previousApp: String?

    private init() {}

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard workspaceObserver == nil else { return }

        previousApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let self = self, let bundleID = app?.bundleIdentifier else { return }

            // Record the layout for the app being left before switching away,
            // so every app gets remembered from ordinary use. Waiting for the
            // user to change layouts would only ever learn a handful of apps.
            if let leaving = self.previousApp, leaving != bundleID {
                self.record(InputSource.current(), for: leaving)
            }
            self.previousApp = bundleID
            self.restoreLayout(for: bundleID)
        }

        inputSourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.recordCurrentLayout()
        }
    }

    private func stop() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        if let observer = inputSourceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            inputSourceObserver = nil
        }
    }

    // MARK: - Storage

    private var layoutsByApp: [String: String] {
        get { defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: storageKey) }
    }

    private func restoreLayout(for bundleID: String) {
        guard let layoutID = layoutsByApp[bundleID],
              layoutID != InputSource.current(),
              KeyboardLayouts.layout(id: layoutID) != nil
        else { return }

        isRestoring = true
        InputSource.select(id: layoutID)
        // The change notification arrives asynchronously; let it pass before
        // listening again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isRestoring = false
        }
    }

    private func recordCurrentLayout() {
        guard !isRestoring,
              let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return }
        record(InputSource.current(), for: bundleID)
    }

    private func record(_ layoutID: String?, for bundleID: String) {
        // Our own panel takes focus while the user edits settings; that isn't an
        // app whose layout is worth remembering.
        guard let layoutID = layoutID, bundleID != Bundle.main.bundleIdentifier else { return }

        var layouts = layoutsByApp
        guard layouts[bundleID] != layoutID else { return }
        layouts[bundleID] = layoutID
        layoutsByApp = layouts
    }
}

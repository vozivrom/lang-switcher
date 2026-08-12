import Foundation

/// Drives update checks and installs, and keeps `AppState` describing what is
/// happening — so the button can say what it will do, and say it only once.
///
/// Both the daily timer and the button in the panel go through here, the
/// difference being that the timer installs what it finds while a person
/// pressing the button is asked first.
final class UpdateController {
    static let shared = UpdateController()
    private init() {}

    /// - Parameter installWhenFound: true for the automatic check.
    func check(installWhenFound: Bool) {
        let state = AppState.shared
        guard !state.isCheckingUpdate, !state.isInstallingUpdate else { return }

        state.isCheckingUpdate = true
        state.updateStatus = nil

        UpdateChecker.check { version in
            state.isCheckingUpdate = false
            state.availableUpdate = version

            guard let version = version else {
                state.updateStatus = "Up to date"
                return
            }
            state.updateStatus = "\(version) available"
            if installWhenFound { self.install() }
        }
    }

    func install() {
        let state = AppState.shared
        guard let version = state.availableUpdate, !state.isInstallingUpdate else { return }

        state.isInstallingUpdate = true
        state.updateStatus = nil

        Updater.install(version: version) { result in
            state.isInstallingUpdate = false
            // On success the app is replaced and relaunched, so only a failure
            // has anything left to report.
            if case .failure(let error) = result {
                state.updateStatus = error.localizedDescription
            }
        }
    }

    /// Forgets anything a previous check reported.
    func reset() {
        let state = AppState.shared
        state.availableUpdate = nil
        state.updateStatus = nil
        state.isCheckingUpdate = false
        state.isInstallingUpdate = false
    }
}

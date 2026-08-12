import Foundation
import Combine

/// Whether the hotkey is actually live, so the settings panel can tell the
/// difference between "permission missing" and "working fine".
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isListening = false

    /// Version of a newer release, once one has been seen.
    @Published var availableUpdate: String?

    /// Why the last update attempt failed, if it did. Progress is shown on the
    /// button itself rather than here.
    @Published var updateStatus: String?

    /// An update is being downloaded and installed right now.
    @Published var isInstallingUpdate = false

    /// A check is in flight.
    @Published var isCheckingUpdate = false
    private init() {}
}

import Foundation
import Combine

/// Whether the hotkey is actually live, so the settings panel can tell the
/// difference between "permission missing" and "working fine".
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isListening = false

    /// Version of a newer release, once one has been seen.
    @Published var availableUpdate: String?
    private init() {}
}

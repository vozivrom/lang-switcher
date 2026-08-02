import Foundation
import Combine

enum Scope: String, CaseIterable {
    case word
    case text
}

/// User preferences, persisted automatically in UserDefaults.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let languages = "cycleLanguages"
        static let scope = "scope"
    }

    /// Ordered list of layout ids the double-shift cycles through.
    @Published var languageIDs: [String] {
        didSet { defaults.set(languageIDs, forKey: Key.languages) }
    }

    /// Whether a double-shift (with no selection) acts on the last word or all text.
    @Published var scope: Scope {
        didSet { defaults.set(scope.rawValue, forKey: Key.scope) }
    }

    private init() {
        languageIDs = (defaults.array(forKey: Key.languages) as? [String]) ?? ["ru", "en", "uk"]
        scope = Scope(rawValue: defaults.string(forKey: Key.scope) ?? "") ?? .word
    }

    /// The cycle resolved to concrete layouts (unknown ids are dropped).
    var cycle: [Layout] { languageIDs.compactMap { LayoutCatalog.byID[$0] } }

    // MARK: - Editing the cycle

    /// Cycling is meaningless with fewer than two layouts, so removal stops here.
    static let minimumLanguages = 2

    /// Layouts from the catalog that aren't in the cycle yet.
    var availableToAdd: [Layout] {
        LayoutCatalog.all.filter { !languageIDs.contains($0.id) }
    }

    var canRemove: Bool { languageIDs.count > Self.minimumLanguages }

    func add(_ id: String) {
        guard LayoutCatalog.byID[id] != nil, !languageIDs.contains(id) else { return }
        languageIDs.append(id)
    }

    func remove(_ id: String) {
        guard canRemove, let index = languageIDs.firstIndex(of: id) else { return }
        languageIDs.remove(at: index)
    }

    /// Reorders the cycle, matching SwiftUI's `onMove` semantics (`destination`
    /// is an offset into the list *before* the move). Implemented here so the
    /// model doesn't depend on SwiftUI.
    func move(from source: IndexSet, to destination: Int) {
        let ascending = source.sorted()
        guard let first = ascending.first, first >= 0,
              let last = ascending.last, last < languageIDs.count else { return }

        let moving = ascending.map { languageIDs[$0] }
        var result = languageIDs
        for index in ascending.reversed() {
            result.remove(at: index)
        }
        let adjusted = destination - ascending.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: min(max(adjusted, 0), result.count))
        languageIDs = result
    }
}

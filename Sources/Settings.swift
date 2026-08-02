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
        static let layouts = "cycleLayoutIDs"
        static let legacyLanguages = "cycleLanguages"   // pre-1.2 language codes
        static let scope = "scope"
        static let rememberPerApp = "rememberLayoutPerApp"
        static let hotkey = "hotkeyModifier"
    }

    /// Ordered list of layout ids the double-shift cycles through.
    @Published var layoutIDs: [String] {
        didSet {
            defaults.set(layoutIDs, forKey: Key.layouts)
            guard layoutIDs.count != oldValue.count else { return }
            // The list grows a row per layout; let the panel resize around it.
            NotificationCenter.default.post(name: .settingsContentResized, object: nil)
        }
    }

    /// Whether a double-shift (with no selection) acts on the last word or all text.
    @Published var scope: Scope {
        didSet { defaults.set(scope.rawValue, forKey: Key.scope) }
    }

    /// The modifier double-tapped to convert.
    @Published var hotkey: HotkeyModifier {
        didSet {
            defaults.set(hotkey.rawValue, forKey: Key.hotkey)
            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
        }
    }

    /// Restore each app's last layout when switching to it.
    @Published var rememberLayoutPerApp: Bool {
        didSet {
            defaults.set(rememberLayoutPerApp, forKey: Key.rememberPerApp)
            AppLayoutMemory.shared.setEnabled(rememberLayoutPerApp)
        }
    }

    private init() {
        scope = Scope(rawValue: defaults.string(forKey: Key.scope) ?? "") ?? .word
        rememberLayoutPerApp = defaults.bool(forKey: Key.rememberPerApp)
        hotkey = HotkeyModifier(rawValue: defaults.string(forKey: Key.hotkey) ?? "") ?? .shift

        if let stored = defaults.array(forKey: Key.layouts) as? [String] {
            layoutIDs = Settings.installed(stored)
        } else if let legacy = defaults.array(forKey: Key.legacyLanguages) as? [String] {
            // Earlier versions stored language codes ("ru", "en") against a
            // hardcoded table; resolve them to actual installed layouts.
            layoutIDs = Settings.installed(legacy)
        } else {
            layoutIDs = KeyboardLayouts.all.map(\.id)
        }

        if layoutIDs.count < Settings.minimumLayouts {
            layoutIDs = KeyboardLayouts.all.map(\.id)
        }

        // didSet doesn't fire during init, so persist the resolved list here —
        // otherwise a migrated or defaulted cycle is recomputed every launch.
        defaults.set(layoutIDs, forKey: Key.layouts)
    }

    /// Maps stored ids — layout ids or legacy language codes — onto the layouts
    /// actually installed, dropping any that no longer exist.
    private static func installed(_ ids: [String]) -> [String] {
        var resolved: [String] = []
        for id in ids {
            let match = KeyboardLayouts.layout(id: id)?.id
                ?? KeyboardLayouts.all.first { $0.languages.contains(id) }?.id
            if let match = match, !resolved.contains(match) {
                resolved.append(match)
            }
        }
        return resolved
    }

    /// The cycle resolved to concrete layouts (unknown ids are dropped).
    var cycle: [Layout] { layoutIDs.compactMap { KeyboardLayouts.layout(id: $0) } }

    // MARK: - Editing the cycle

    /// Cycling is meaningless with fewer than two layouts, so removal stops here.
    static let minimumLayouts = 2

    /// Installed layouts that aren't in the cycle yet.
    var availableToAdd: [Layout] {
        KeyboardLayouts.all.filter { !layoutIDs.contains($0.id) }
    }

    var canRemove: Bool { layoutIDs.count > Settings.minimumLayouts }

    func add(_ id: String) {
        guard KeyboardLayouts.layout(id: id) != nil, !layoutIDs.contains(id) else { return }
        layoutIDs.append(id)
    }

    func remove(_ id: String) {
        guard canRemove, let index = layoutIDs.firstIndex(of: id) else { return }
        layoutIDs.remove(at: index)
    }

    /// Reorders the cycle, matching SwiftUI's `onMove` semantics (`destination`
    /// is an offset into the list *before* the move). Implemented here so the
    /// model doesn't depend on SwiftUI.
    func move(from source: IndexSet, to destination: Int) {
        let ascending = source.sorted()
        guard let first = ascending.first, first >= 0,
              let last = ascending.last, last < layoutIDs.count else { return }

        let moving = ascending.map { layoutIDs[$0] }
        var result = layoutIDs
        for index in ascending.reversed() {
            result.remove(at: index)
        }
        let adjusted = destination - ascending.filter { $0 < destination }.count
        result.insert(contentsOf: moving, at: min(max(adjusted, 0), result.count))
        layoutIDs = result
    }
}

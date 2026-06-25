import Foundation
import Carbon

/// Switches the active system keyboard input source to one that supports a
/// given language (e.g. "en" -> ABC/U.S., "ru" -> Russian).
enum InputSource {

    /// Selects the first enabled, selectable keyboard layout whose language
    /// list matches `language`. No-op if none is installed.
    static func select(language: String) {
        let filter = [kTISPropertyInputSourceCategory as String:
                        kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              let sources = cfList as? [TISInputSource] else { return }

        for source in sources where isSelectable(source) {
            guard let langs = languages(of: source) else { continue }
            if langs.contains(where: { $0 == language || $0.hasPrefix(language + "-") }) {
                TISSelectInputSource(source)
                return
            }
        }
    }

    private static func isSelectable(_ source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    private static func languages(of source: TISInputSource) -> [String]? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return nil
        }
        return Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String]
    }
}

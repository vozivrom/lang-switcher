import Foundation
import Carbon

/// Switches the active system keyboard to a specific installed layout.
enum InputSource {

    /// Selects the input source with this id (e.g. "com.apple.keylayout.Russian").
    /// No-op if it isn't installed or can't be selected.
    static func select(id: String) {
        let filter = [kTISPropertyInputSourceCategory as String:
                        kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              let sources = list as? [TISInputSource] else { return }

        for source in sources where isSelectable(source) {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                  let sourceID = Unmanaged<AnyObject>.fromOpaque(pointer)
                      .takeUnretainedValue() as? String,
                  sourceID == id
            else { continue }
            TISSelectInputSource(source)
            return
        }
    }

    /// The id of the keyboard layout currently in use.
    static func current() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? String
    }

    private static func isSelectable(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }
}

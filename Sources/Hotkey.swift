import Foundation
import CoreGraphics

/// The modifier whose double-tap triggers a conversion.
///
/// Only modifiers work as the trigger: they produce no character of their own,
/// so tapping one twice can't be confused with typing.
enum HotkeyModifier: String, CaseIterable, Identifiable {
    case shift
    case command
    case option
    case control

    var id: String { rawValue }

    var name: String {
        switch self {
        case .shift:   return "Shift"
        case .command: return "Command"
        case .option:  return "Option"
        case .control: return "Control"
        }
    }

    var symbol: String {
        switch self {
        case .shift:   return "⇧"
        case .command: return "⌘"
        case .option:  return "⌥"
        case .control: return "⌃"
        }
    }

    /// Left and right hardware keycodes for this modifier.
    var keyCodes: Set<Int64> {
        switch self {
        case .shift:   return [56, 60]
        case .command: return [55, 54]
        case .option:  return [58, 61]
        case .control: return [59, 62]
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .shift:   return .maskShift
        case .command: return .maskCommand
        case .option:  return .maskAlternate
        case .control: return .maskControl
        }
    }
}

import Cocoa
import QuartzCore

/// Watches the global keyboard event stream and fires `onDoubleShift` when the
/// Shift key is pressed twice in quick succession with no other key in between.
final class DoubleShiftDetector {

    /// Maximum time between the two Shift presses to count as a double-tap.
    var maxInterval: CFTimeInterval = 0.35

    /// Set true while we are synthesizing our own copy/paste keystrokes so the
    /// synthetic Shift in ⇧⌥← cannot retrigger detection. Un-pausing clears the
    /// transient Shift state, because our synthetic keystrokes (and the swallowed
    /// release of the triggering Shift) leave `shiftWasDown` out of sync with the
    /// physical key.
    var isPaused = false {
        didSet {
            if !isPaused {
                shiftWasDown = false
                lastShiftPress = 0
            }
        }
    }

    var onDoubleShift: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastShiftPress: CFTimeInterval = 0
    private var shiftWasDown = false

    private static let leftShift: Int64 = 56
    private static let rightShift: Int64 = 60

    /// Creates and enables the event tap. Returns false if the process is not
    /// trusted for Accessibility yet (caller should retry once permission is granted).
    @discardableResult
    func enable() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<DoubleShiftDetector>.fromOpaque(refcon!).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The system may disable the tap if our callback is ever too slow.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        if isPaused { return }

        // Any real key press breaks a pending Shift-Shift sequence (e.g. Shift+A).
        if type == .keyDown {
            lastShiftPress = 0
            return
        }

        guard type == .flagsChanged else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if keyCode == DoubleShiftDetector.leftShift || keyCode == DoubleShiftDetector.rightShift {
            let down = event.flags.contains(.maskShift)
            if down && !shiftWasDown {
                let now = CACurrentMediaTime()
                if now - lastShiftPress <= maxInterval {
                    lastShiftPress = 0
                    onDoubleShift?()
                } else {
                    lastShiftPress = now
                }
            }
            shiftWasDown = down
        } else {
            // A different modifier (⌘/⌥/⌃/Caps) toggled -> not a clean double Shift.
            lastShiftPress = 0
        }
    }
}

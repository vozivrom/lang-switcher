import Cocoa
import QuartzCore

/// Watches the global keyboard event stream and fires `onDoubleTap` when the
/// chosen modifier is pressed twice in quick succession with no other key in
/// between.
final class DoubleTapDetector {

    /// Which modifier triggers a conversion. Changing it clears any half-finished
    /// tap, so a press of the old modifier can't pair with one of the new.
    var modifier: HotkeyModifier = .shift {
        didSet {
            guard modifier != oldValue else { return }
            lastPress = 0
            modifierWasDown = false
        }
    }

    /// Maximum time between the two presses to count as a double-tap.
    var maxInterval: CFTimeInterval = 0.35

    /// Set true while we are synthesizing our own copy/paste keystrokes so the
    /// synthetic Shift in ⇧⌥← cannot retrigger detection. Un-pausing clears the
    /// transient state, because our synthetic keystrokes (and the swallowed
    /// release of the triggering key) leave `modifierWasDown` out of sync with
    /// the physical key.
    var isPaused = false {
        didSet {
            if !isPaused {
                modifierWasDown = false
                lastPress = 0
            }
        }
    }

    var onDoubleTap: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var lastPress: CFTimeInterval = 0
    private var modifierWasDown = false

    /// Creates and enables the event tap. Returns false if the process is not
    /// trusted for Accessibility yet (caller should retry once permission is granted).
    @discardableResult
    func enable() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<DoubleTapDetector>.fromOpaque(refcon!).takeUnretainedValue()
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

        // Never count keystrokes we posted ourselves.
        if event.getIntegerValueField(.eventSourceUserData) == Switcher.syntheticTag { return }

        if isPaused { return }

        // Any real key press breaks a pending sequence (e.g. Shift+A).
        if type == .keyDown {
            lastPress = 0
            return
        }

        guard type == .flagsChanged else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if modifier.keyCodes.contains(keyCode) {
            let down = event.flags.contains(modifier.flag)
            if down && !modifierWasDown {
                let now = CACurrentMediaTime()
                if now - lastPress <= maxInterval {
                    lastPress = 0
                    onDoubleTap?()
                } else {
                    lastPress = now
                }
            }
            modifierWasDown = down
        } else {
            // A different modifier toggled -> not a clean double tap.
            lastPress = 0
        }
    }
}

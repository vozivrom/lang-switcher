import Cocoa
import SwiftUI
import QuartzCore

/// A borderless panel that can become key (so SwiftUI controls work) and draws
/// as a plain rounded rectangle — no popover arrow.
private final class MenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Owns the menu-bar icon and the settings panel shown beneath it.
final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem?
    private var panel: MenuPanel?
    private var clickMonitor: Any?
    private var resizeObserver: NSObjectProtocol?
    private var hostingView: NSHostingView<SettingsView>?
    private var lastCloseTime: CFTimeInterval = 0

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "LangSwitcher")
            button.action = #selector(toggle)
            button.target = self
        }
        statusItem = item
    }

    @objc private func toggle() {
        if let panel = panel, panel.isVisible {
            closePanel()
            return
        }
        // The same click that closed the panel (via resign-key) also fires this
        // action — don't immediately reopen.
        if CACurrentMediaTime() - lastCloseTime < 0.2 { return }
        openPanel()
    }

    private func openPanel() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        // Pick up layouts added or removed in System Settings since last time.
        KeyboardLayouts.refresh()
        Settings.shared.pruneMissingLayouts()

        let hosting = NSHostingView(rootView: SettingsView(settings: Settings.shared))
        let size = hosting.fittingSize
        hostingView = hosting

        // NSVisualEffectView with .behindWindow blending is what actually blurs
        // the desktop behind the panel (a SwiftUI Material can't). The hosting
        // view sits on top with a transparent background so the blur shows.
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        blur.addSubview(hosting)

        let panel = MenuPanel(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.contentView = blur

        // Position centered under the menu-bar icon.
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let origin = NSPoint(x: screenRect.midX - size.width / 2,
                             y: screenRect.minY - size.height - 6)
        panel.setFrameOrigin(origin)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        NotificationCenter.default.addObserver(self, selector: #selector(closePanel),
                                               name: NSWindow.didResignKeyNotification, object: panel)
        // Any click outside our panel (another menu-bar item, another app, the
        // desktop) dismisses it. Clicks inside the panel are local events, which
        // a global monitor doesn't see, so they don't close it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePanel()
        }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: .settingsContentResized, object: nil, queue: .main
        ) { [weak self] _ in
            self?.resizeToFitContent()
        }
    }

    /// Grows or shrinks the panel around its content, keeping the top edge
    /// pinned under the menu bar icon so it doesn't appear to jump.
    private func resizeToFitContent() {
        guard let panel = panel, let hosting = hostingView else { return }
        hosting.layoutSubtreeIfNeeded()

        let size = hosting.fittingSize
        var frame = panel.frame
        let top = frame.origin.y + frame.height
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true, animate: false)
    }

    @objc private func closePanel() {
        guard let panel = panel else { return }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: panel)
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
        panel.orderOut(nil)
        self.panel = nil
        hostingView = nil
        lastCloseTime = CACurrentMediaTime()
    }
}

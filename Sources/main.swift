import Cocoa

// Two copies running at once each invalidate the other's Accessibility grant,
// which looks like the app forgetting its permission. Stand down and let the
// one that got here first keep it.
if let running = Instance.alreadyRunning() {
    running.activate()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar

let controller = AppController()
controller.start()

app.run()

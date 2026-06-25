import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar

let controller = AppController()
controller.start()

app.run()

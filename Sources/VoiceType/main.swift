import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon — floating window still works

let delegate = AppDelegate()
app.delegate = delegate
app.run()

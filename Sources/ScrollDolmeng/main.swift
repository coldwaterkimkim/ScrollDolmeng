import AppKit

let app = NSApplication.shared
let appController = AppController()

app.setActivationPolicy(.accessory)
app.delegate = appController
app.run()

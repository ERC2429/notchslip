import AppKit

setbuf(stdout, nil)
print("[NotchSlip] main start")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
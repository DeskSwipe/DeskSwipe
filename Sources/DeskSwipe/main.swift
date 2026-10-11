import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only. LSUIElement in Info.plist also hides the Dock icon when
// running as DeskSwipe.app; this covers `swift run` as well.
app.setActivationPolicy(.accessory)
app.run()

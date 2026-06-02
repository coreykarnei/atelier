import AppKit

// Atelier — a single-window, native macOS workspace for agent-assisted coding.
// SwiftPM executable bootstrap: no .xib, no storyboard. We drive NSApplication
// programmatically (.regular so it's a normal windowed app with a Dock icon).

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

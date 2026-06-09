import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private let notificationServer = NotificationServer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menu.build()
        notificationServer.start()

        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.startProcesses()
        mainWindowController = controller

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        notificationServer.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Menu actions

    /// `⌘\` — forward the layout toggle to the window controller. The nil-targeted
    /// menu item reaches here through the responder chain. (M1.3 will route to the
    /// key window's controller once there is more than one window.)
    @objc func toggleLayout(_ sender: Any?) {
        mainWindowController?.toggleLayout()
    }
}

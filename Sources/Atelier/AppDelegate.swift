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
}

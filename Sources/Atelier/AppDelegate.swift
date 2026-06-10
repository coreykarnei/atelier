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

    // Nil-targeted menu items reach here through the responder chain. (M1.3 will
    // route to the key window's controller once there is more than one window.)

    @objc func toggleLayout(_ sender: Any?) { mainWindowController?.toggleLayout() }

    @objc func newSession(_ sender: Any?) { mainWindowController?.addSession() }
    @objc func openIDEHere(_ sender: Any?) { mainWindowController?.promoteActiveSessionHere() }
    @objc func closeSession(_ sender: Any?) { mainWindowController?.closeActiveSession() }
    @objc func nextSession(_ sender: Any?) { mainWindowController?.selectNext() }
    @objc func prevSession(_ sender: Any?) { mainWindowController?.selectPrev() }

    @objc func focusLeft(_ sender: Any?) { mainWindowController?.focusPane(.left) }
    @objc func focusDown(_ sender: Any?) { mainWindowController?.focusPane(.down) }
    @objc func focusUp(_ sender: Any?) { mainWindowController?.focusPane(.up) }
    @objc func focusRight(_ sender: Any?) { mainWindowController?.focusPane(.right) }
}

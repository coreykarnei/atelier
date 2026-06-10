import AppKit

/// One app, N project windows (MILESTONE_1 §2): each `MainWindowController` is one
/// project; macOS native window tabbing draws the always-visible project strip in
/// the titlebar. `⌘T` opens a new project tab (a Landing, which *becomes* the
/// project when promoted); session-level actions route to the key window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [MainWindowController] = []
    private let notificationServer = NotificationServer()

    /// The controller behind the key window — where session-level menu actions land.
    private var keyController: MainWindowController? {
        (NSApp.keyWindow?.windowController as? MainWindowController) ?? controllers.last
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Menu.build()
        if let windowMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Window" })?.submenu {
            NSApp.windowsMenu = windowMenu
        }
        notificationServer.start()

        openProjectWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in controllers { controller.terminateAllSessions() }
        notificationServer.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: Project windows

    /// Open a new project tab: a window starting as a Landing. Joins the key
    /// window's native tab group so projects line up in the titlebar strip.
    @discardableResult
    private func openProjectWindow() -> MainWindowController {
        let controller = MainWindowController()
        controllers.append(controller)

        if let window = controller.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window
            )
            if let anchor = NSApp.keyWindow ?? controllers.dropLast().last?.window {
                anchor.addTabbedWindow(window, ordered: .above)
            }
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.startProcesses()
        return controller
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        if let index = controllers.firstIndex(where: { $0.window === window }) {
            controllers[index].terminateAllSessions()
            controllers.remove(at: index)
        }
    }

    // MARK: Menu actions (responder chain)

    @objc func newProject(_ sender: Any?) { openProjectWindow() }

    /// `⌘1..9` — focus the Nth project tab (menu item tag carries N).
    @objc func selectProject(_ sender: NSMenuItem) {
        let windows = NSApp.keyWindow?.tabGroup?.windows ?? controllers.compactMap(\.window)
        let index = sender.tag - 1
        guard windows.indices.contains(index) else { return }
        windows[index].makeKeyAndOrderFront(nil)
    }

    @objc func toggleLayout(_ sender: Any?) { keyController?.toggleLayout() }

    @objc func newSession(_ sender: Any?) { keyController?.addSessionOnCurrentRoot() }
    @objc func openIDEHere(_ sender: Any?) { keyController?.promoteActiveSessionHere() }
    @objc func closeSession(_ sender: Any?) { keyController?.closeActiveSession() }
    @objc func nextSession(_ sender: Any?) { keyController?.selectNext() }
    @objc func prevSession(_ sender: Any?) { keyController?.selectPrev() }

    @objc func focusLeft(_ sender: Any?) { keyController?.focusPane(.left) }
    @objc func focusDown(_ sender: Any?) { keyController?.focusPane(.down) }
    @objc func focusUp(_ sender: Any?) { keyController?.focusPane(.up) }
    @objc func focusRight(_ sender: Any?) { keyController?.focusPane(.right) }
}

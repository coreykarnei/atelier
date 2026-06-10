import AppKit
import AtelierIPC

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
        notificationServer.onCommand = { [weak self] command in self?.handle(command) }
        notificationServer.start()

        restoreOrOpenFresh()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Persistence (MILESTONE_1 §9)

    /// Snapshot before windows tear down — `applicationWillTerminate` is too late,
    /// the controllers are already gone by then. Closing every window by hand
    /// quits without a snapshot; that's deliberate ("I closed my projects").
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let state = PersistedState(
            windows: controllers.map { $0.persisted() },
            activeWindow: controllers.firstIndex { $0.window === NSApp.keyWindow } ?? 0
        )
        SessionStore.save(state)
        return .terminateNow
    }

    /// Restore the saved workspace; validate every session root first (§9.1):
    /// an orphaned root is surfaced and dropped — never silently dropped,
    /// reparented, or resurrected.
    private func restoreOrOpenFresh() {
        guard let state = SessionStore.load(), !state.windows.isEmpty else {
            openProjectWindow()
            return
        }

        var orphans: [String] = []
        var restoredAny = false
        for window in state.windows {
            let valid = window.sessions.filter { session in
                var isDir: ObjCBool = false
                let ok = FileManager.default.fileExists(atPath: session.cwd, isDirectory: &isDir) && isDir.boolValue
                if !ok { orphans.append(session.title) }
                return ok
            }
            guard !valid.isEmpty else { continue }
            var pruned = window
            pruned.sessions = valid
            pruned.activeIndex = min(window.activeIndex, valid.count - 1)
            restoreProjectWindow(pruned)
            restoredAny = true
        }
        if !restoredAny { openProjectWindow() }

        if !orphans.isEmpty {
            let alert = NSAlert()
            alert.messageText = orphans.count == 1
                ? "1 session wasn't restored"
                : "\(orphans.count) sessions weren't restored"
            alert.informativeText = "Their worktrees no longer exist: "
                + orphans.joined(separator: ", ")
                + ". Recreate a worktree from the branch pill if you need one back."
            alert.addButton(withTitle: "OK")
            if let window = NSApp.keyWindow {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    private func restoreProjectWindow(_ persisted: PersistedWindow) {
        let controller = MainWindowController(restored: persisted)
        controllers.append(controller)
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window
            )
            if let anchor = controllers.dropLast().last?.window {
                anchor.addTabbedWindow(window, ordered: .above)
            }
        }
        controller.showWindow(nil)
        controller.startProcesses()
    }

    /// A command from the `atelier` CLI: route to the project window anchored to
    /// the target's primary checkout, opening one if none exists.
    private func handle(_ command: CommandMessage) {
        let root = WorktreeManager.repoRoot(for: command.path) ?? command.path
        let controller = controllers.first { $0.projectRepoRoot == root }

        switch command.verb {
        case .open:
            let target = controller ?? openProjectWindow(root: root)
            target.window?.makeKeyAndOrderFront(nil)
        case .worktreeAdd:
            guard let branch = command.branch else { return }
            let target = controller ?? openProjectWindow(root: root)
            target.window?.makeKeyAndOrderFront(nil)
            target.openWorktree(branch: branch)
        case .worktreeRemove:
            guard let branch = command.branch, let controller else { return }
            controller.window?.makeKeyAndOrderFront(nil)
            controller.removeWorktree(branch: branch)
        }
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

    /// Open a new project tab — a Landing, or directly on `root` (CLI). Joins the
    /// key window's native tab group so projects line up in the titlebar strip.
    @discardableResult
    private func openProjectWindow(root: String? = nil) -> MainWindowController {
        let controller = MainWindowController(root: root)
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

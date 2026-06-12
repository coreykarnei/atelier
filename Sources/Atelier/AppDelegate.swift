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
        // Tab badges (§7.1): route each agent event to whichever window owns the
        // session; banner clicks focus that session's tab.
        notificationServer.onAgentEvent = { [weak self] message in
            guard let self, message.sessionId != nil else { return }
            for controller in self.controllers where controller.applyAgentEvent(message) {
                break
            }
        }
        notificationServer.onNotificationClick = { [weak self] sessionId in
            guard let self else { return }
            for controller in self.controllers where controller.focusSession(claudeSessionId: sessionId) {
                NSApp.activate(ignoringOtherApps: true)
                break
            }
        }
        notificationServer.onDebug = { [weak self] debug in self?.handle(debug) }
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
        isTerminating = true
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

        var orphans: [(title: String, branch: String)] = []
        var restoredAny = false
        for window in state.windows {
            let valid = window.sessions.filter { session in
                var isDir: ObjCBool = false
                let ok = FileManager.default.fileExists(atPath: session.cwd, isDirectory: &isDir) && isDir.boolValue
                if !ok { orphans.append((session.title, (session.cwd as NSString).lastPathComponent)) }
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
            // A designed refusal (§5): Atelier speaks the sentence, the dead
            // worktrees are named in mono, and one button opens the fan aimed
            // at recreating the first of them.
            let alert = NSAlert()
            alert.messageText = orphans.count == 1
                ? "1 session wasn't restored"
                : "\(orphans.count) sessions weren't restored"
            alert.informativeText = "Their worktrees no longer exist. Recreating one starts that branch fresh — the old checkout is gone."
            let label = NSTextField(labelWithString: orphans.map { "⎇ \($0.branch)" }.joined(separator: "\n"))
            label.font = Theme.Typography.mono(Theme.Typography.small)
            label.textColor = Theme.chromeText
            label.frame = NSRect(x: 0, y: 0, width: 320, height: label.fittingSize.height)
            alert.accessoryView = label
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Recreate…")
            let recreate = { [weak self] (response: NSApplication.ModalResponse) in
                guard response == .alertSecondButtonReturn, let self else { return }
                self.keyController?.showWorktreeFan(prefill: orphans.first?.branch)
            }
            if let window = NSApp.keyWindow {
                alert.beginSheetModal(for: window, completionHandler: recreate)
            } else {
                recreate(alert.runModal())
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

    /// The Dock badge (§4): the count of sessions across all windows whose
    /// state means *your move is the bottleneck* — unseen completions and
    /// explicit blocks only. Not blue (the agent is fine without you), not
    /// plain peach (you saw it finish). Zero shows no badge.
    func refreshDockBadge() {
        let count = controllers.reduce(0) { $0 + $1.actionableSessionCount }
        NSApp.dockTile.badgeLabel = count == 0 ? nil : String(count)
    }

    /// Dev-only (`DebugMessage`): self-capture every visible window to PNGs.
    /// Renders the app's own view tree, so it needs no Screen Recording grant;
    /// note the behind-window blur is composited by the WindowServer and won't
    /// appear — judge translucency live, use these for layout/type/color.
    private func handle(_ debug: DebugMessage) {
        guard debug.debug == .snapshot else { return }
        let dir = URL(fileURLWithPath: debug.path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, window) in NSApp.windows.enumerated() where window.isVisible {
            guard let view = window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let name = "atelier-\(index)-\(window.title.isEmpty ? "untitled" : window.title).png"
            try? png.write(to: dir.appendingPathComponent(name))
        }
        NSLog("Atelier: debug snapshot written to \(debug.path)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        for controller in controllers { controller.terminateAllSessions() }
        notificationServer.stop()
    }

    /// Closing the last project tab kicks back to the Launch view, not out of the
    /// app: a fresh Landing window opens in its place (unless we're quitting).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private var isTerminating = false

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
        // Last project tab closed → back to the Launch view (a fresh Landing),
        // not out of the app. Deferred so the close finishes unwinding first.
        if controllers.isEmpty, !isTerminating {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.controllers.isEmpty, !self.isTerminating else { return }
                self.openProjectWindow()
            }
        }
    }

    // MARK: Menu actions (responder chain)

    @objc func newProject(_ sender: Any?) { openProjectWindow() }
    @objc func showPalette(_ sender: Any?) { keyController?.showPalette() }

    /// Switch targets for the palette: every other project window, by title.
    func otherProjects(excluding: MainWindowController) -> [(String, NSWindow)] {
        controllers.compactMap { controller in
            guard controller !== excluding, let window = controller.window else { return nil }
            return (window.title, window)
        }
    }

    /// `⌘1..9` — focus the Nth project tab (menu item tag carries N).
    @objc func selectProject(_ sender: NSMenuItem) {
        let windows = NSApp.keyWindow?.tabGroup?.windows ?? controllers.compactMap(\.window)
        let index = sender.tag - 1
        guard windows.indices.contains(index) else { return }
        windows[index].makeKeyAndOrderFront(nil)
    }

    @objc func toggleLayout(_ sender: Any?) { keyController?.toggleLayout() }

    @objc func newSession(_ sender: Any?) { keyController?.addSessionOnMain() }
    @objc func openIDEHere(_ sender: Any?) { keyController?.promoteActiveSessionHere() }
    @objc func closeSession(_ sender: Any?) { keyController?.closeActiveSession() }
    @objc func nextSession(_ sender: Any?) { keyController?.selectNext() }
    @objc func prevSession(_ sender: Any?) { keyController?.selectPrev() }

    @objc func focusLeft(_ sender: Any?) { keyController?.focusPane(.left) }
    @objc func focusDown(_ sender: Any?) { keyController?.focusPane(.down) }
    @objc func focusUp(_ sender: Any?) { keyController?.focusPane(.up) }
    @objc func focusRight(_ sender: Any?) { keyController?.focusPane(.right) }
}

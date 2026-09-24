import AppKit
import AtelierIPC

/// One app, one workspace window, N project tabs (MILESTONE_1 §2, single
/// window since 2026-09-10): each `ProjectController` is one project;
/// `WorkspaceWindowController` draws the always-visible project strip in the
/// titlebar. `⌘T` opens a new project tab (a Landing, which *becomes* the
/// project when promoted); session-level actions route to the active project.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var workspace: WorkspaceWindowController?
    private let notificationServer = NotificationServer()

    private var projects: [ProjectController] { workspace?.projects ?? [] }

    /// The project on screen — where session-level menu actions land.
    private var keyController: ProjectController? { workspace?.activeProject }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginEnvironment.prefetch()
        NSApp.mainMenu = Menu.build()
        if let windowMenu = NSApp.mainMenu?.items.first(where: { $0.submenu?.title == "Window" })?.submenu {
            NSApp.windowsMenu = windowMenu
        }
        notificationServer.onCommand = { [weak self] command in self?.handle(command) }
        // Tab badges (§7.1): route each agent event to whichever window owns the
        // session; banner clicks focus that session's tab.
        notificationServer.onAgentEvent = { [weak self] message in
            guard let self, message.sessionId != nil else { return }
            for controller in self.projects where controller.applyAgentEvent(message) {
                break
            }
        }
        notificationServer.onNotificationClick = { [weak self] sessionId in
            guard let self else { return }
            for controller in self.projects where controller.focusSession(claudeSessionId: sessionId) {
                NSApp.activate(ignoringOtherApps: true)
                break
            }
        }
        notificationServer.onDebug = { [weak self] debug in self?.handle(debug) }
        if ProcessInfo.processInfo.environment["ATELIER_LSP_TRACE"] != nil {
            let log = NSHomeDirectory() + "/.local/state/atelier/lsp.log"
            LSPClient.debugTrace = { line in
                if let handle = FileHandle(forWritingAtPath: log) ?? (FileManager.default.createFile(atPath: log, contents: nil) ? FileHandle(forWritingAtPath: log) : nil) {
                    handle.seekToEndOfFile(); handle.write((line + "\n").data(using: .utf8)!); handle.closeFile()
                }
            }
        }
        notificationServer.start()

        restoreOrOpenFresh()
        if ProcessInfo.processInfo.environment["ATELIER_DEBUG_ATTENTION"] != nil {
            keyController?.debugSeedAttention()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Persistence (MILESTONE_1 §9)

    /// Snapshot before the window tears down — `applicationWillTerminate` is
    /// too late, the projects are already gone by then. The close button
    /// lands here too (`WorkspaceWindowController.windowShouldClose`); only closing the last
    /// project by hand leaves an empty snapshot.
    ///
    /// Dirty editor buffers get the informative refusal first (M2.1's ⌘W
    /// guard, at quit scale): the files are named, saving is one button away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirty = projects.flatMap { $0.dirtyBufferPaths }
        if !dirty.isEmpty {
            let alert = NSAlert()
            alert.messageText = dirty.count == 1
                ? "\((dirty[0] as NSString).lastPathComponent) has unsaved changes"
                : "\(dirty.count) files have unsaved changes"
            alert.informativeText = "Quitting will discard them."
            let label = NSTextField(labelWithString: dirty.map {
                ($0 as NSString).lastPathComponent
            }.joined(separator: "\n"))
            label.font = Theme.Typography.mono(Theme.Typography.small)
            label.textColor = Theme.chromeText
            label.frame = NSRect(x: 0, y: 0, width: 320, height: label.fittingSize.height)
            alert.accessoryView = label
            alert.addButton(withTitle: "Save All and Quit")
            alert.addButton(withTitle: "Discard and Quit")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do {
                    for controller in projects { try controller.saveAllDirtyBuffers() }
                } catch {
                    let failure = NSAlert()
                    failure.alertStyle = .warning
                    failure.messageText = "Couldn't save"
                    failure.informativeText = error.localizedDescription
                    failure.runModal()
                    return .terminateCancel
                }
            case .alertSecondButtonReturn:
                break // discard
            default:
                return .terminateCancel
            }
        }

        let state = PersistedState(
            windows: projects.map { $0.persisted() },
            activeWindow: workspace?.activeIndex ?? 0
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
            openProject()
            return
        }

        var orphans: [(title: String, branch: String)] = []
        var restoredAny = false
        for window in state.windows {
            let valid = window.sessions.filter { session in
                // Remote sessions restore optimistically — no pre-flight ssh
                // (a dead host must not block launch); the reconnecting
                // placard *is* the offline UX.
                if session.remoteHost != nil { return true }
                var isDir: ObjCBool = false
                let ok = FileManager.default.fileExists(atPath: session.cwd, isDirectory: &isDir) && isDir.boolValue
                if !ok { orphans.append((session.title, (session.cwd as NSString).lastPathComponent)) }
                return ok
            }
            guard !valid.isEmpty else { continue }
            var pruned = window
            pruned.sessions = valid
            pruned.activeIndex = min(window.activeIndex, valid.count - 1)
            restoreProject(pruned)
            restoredAny = true
        }
        if !restoredAny {
            openProject()
        } else {
            // Back on the tab that was up at quit (clamped: orphans may have
            // dropped a project).
            workspace?.activate(index: min(state.activeWindow, projects.count - 1))
        }

        if !orphans.isEmpty {
            // A designed refusal (§5): Atelier speaks the sentence, the dead
            // worktrees are named in mono, and one button opens the chooser
            // aimed at recreating the first of them.
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
                self.keyController?.showWorktreeChooser(prefill: orphans.first?.branch)
            }
            if let window = NSApp.keyWindow {
                alert.beginSheetModal(for: window, completionHandler: recreate)
            } else {
                recreate(alert.runModal())
            }
        }
    }

    private func restoreProject(_ persisted: PersistedWindow) {
        let project = ProjectController(restored: persisted)
        ensureWorkspace().add(project, activate: false)
        project.startProcesses()
    }

    /// A command from the `atelier` CLI: route to the project window anchored to
    /// the target's primary checkout, opening one if none exists.
    private func handle(_ command: CommandMessage) {
        let root = WorktreeManager.repoRoot(for: command.path) ?? command.path
        // A window anchored on a repo is matched by that repo; one anchored on
        // a plain folder has no repo root, so it answers to the folder itself.
        let controller = projects.first { ($0.projectRepoRoot ?? $0.projectRoot) == root }

        switch command.verb {
        case .open:
            let target = controller ?? openProject(root: root)
            target.activate()
        case .worktreeAdd:
            guard let branch = command.branch else { return }
            let target = controller ?? openProject(root: root)
            target.activate()
            target.openWorktree(branch: branch)
        case .worktreeRemove:
            guard let branch = command.branch, let controller else { return }
            controller.activate()
            controller.removeWorktree(branch: branch)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The Dock badge (§4): the count of sessions across all windows whose
    /// state means *your move is the bottleneck* — unseen completions and
    /// explicit blocks only. Not blue (the agent is fine without you), not
    /// plain peach (you saw it finish). Zero shows no badge.
    func refreshDockBadge() {
        let count = projects.reduce(0) { $0 + $1.actionableSessionCount }
        NSApp.dockTile.badgeLabel = count == 0 ? nil : String(count)
    }

    /// Dev-only (`DebugMessage`): self-capture every visible window to PNGs.
    /// Renders the app's own view tree, so it needs no Screen Recording grant;
    /// note the behind-window blur is composited by the WindowServer and won't
    /// appear — judge translucency live, use these for layout/type/color.
    private func handle(_ debug: DebugMessage) {
        switch debug.debug {
        case .snapshot:
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
            let state = projects.map(\.debugWashState).joined(separator: "\n")
            try? state.write(to: dir.appendingPathComponent("state.txt"), atomically: true, encoding: .utf8)
            NSLog("Atelier: debug snapshot written to \(debug.path)")
        case .seedAttention:
            keyController?.debugSeedAttention()
        case .toggleExplorer:
            keyController?.toggleExplorer()
        case .explorerSearch:
            keyController?.debugExplorerSearch(debug.path)
        case .lspProbe:
            let path = debug.path
            let controller = keyController ?? projects.first
            guard let controller else {
                try? "lspProbe: no window controller".write(toFile: path, atomically: true, encoding: .utf8)
                return
            }
            controller.lspProbe(line: debug.line ?? 1, column: debug.column ?? 1) { dump in
                try? dump.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Quitting: remote work stays alive on its hosts (reattach on relaunch).
        for controller in projects { controller.terminateAllSessions(killRemote: false) }
        LSPRegistry.terminateAll()
        RemoteLink.terminateAll()
        notificationServer.stop()
    }

    /// Closing the last project window closes the app — the close button means
    /// leave, not "swap my window for a fresh Landing" (owner report
    /// 2026-07-21; the old respawn read as a window that refused to die).
    /// The close button itself is Quit (`windowShouldClose`), so
    /// only closing the last project lands here — nothing left to restore,
    /// and relaunch starts at the Launch view.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var isTerminating = false

    // MARK: Projects

    /// The one window, created on first need and shown.
    private func ensureWorkspace() -> WorkspaceWindowController {
        if let workspace { return workspace }
        let created = WorkspaceWindowController()
        workspace = created
        if let window = created.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose(_:)),
                name: NSWindow.willCloseNotification, object: window
            )
        }
        created.showWindow(nil)
        return created
    }

    /// Open a new project tab — a Landing, or directly on `root` (CLI) — and
    /// bring it on screen.
    @discardableResult
    private func openProject(root: String? = nil) -> ProjectController {
        let project = ProjectController(root: root)
        let workspace = ensureWorkspace()
        workspace.add(project, activate: true)
        workspace.window?.makeKeyAndOrderFront(nil)
        project.startProcesses()
        return project
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow, window === workspace?.window else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        // Outside quit this is the last project closing by hand ("I closed
        // my projects"), which kills remote work too; during quit the snapshot already promised
        // these sessions back, so their remote side must survive.
        for project in projects { project.terminateAllSessions(killRemote: !isTerminating) }
        workspace = nil
    }

    // MARK: Menu actions (responder chain)

    @objc func newProject(_ sender: Any?) { openProject() }
    @objc func closeProject(_ sender: Any?) {
        guard let workspace, let project = workspace.activeProject else { return }
        workspace.close(project)
    }
    @objc func nextProject(_ sender: Any?) { workspace?.activateNext() }
    @objc func prevProject(_ sender: Any?) { workspace?.activatePrevious() }
    @objc func showPalette(_ sender: Any?) { keyController?.showPalette() }
    @objc func showSettings(_ sender: Any?) { SettingsWindowController.shared.show() }

    /// Switch targets for the palette: every other project tab.
    func otherProjects(excluding: ProjectController) -> [ProjectController] {
        projects.filter { $0 !== excluding }
    }

    /// `⌘1..9` — focus the Nth project tab (menu item tag carries N).
    @objc func selectProject(_ sender: NSMenuItem) {
        workspace?.activate(index: sender.tag - 1)
    }

    @objc func toggleLayout(_ sender: Any?) { keyController?.toggleLayout() }

    @objc func newSession(_ sender: Any?) { keyController?.requestNewSession() }
    @objc func newWorktreeSession(_ sender: Any?) { keyController?.bottomBarDidRequestWorktreeSession() }
    @objc func openIDEHere(_ sender: Any?) { keyController?.promoteActiveSessionHere() }
    @objc func closeSession(_ sender: Any?) { keyController?.closeActiveSession() }
    @objc func reopenSession(_ sender: Any?) { keyController?.reopenClosedSession() }

    @objc func openFile(_ sender: Any?) { keyController?.openFileInEditor() }
    @objc func saveFile(_ sender: Any?) { keyController?.saveEditor() }
    @objc func toggleAutosave(_ sender: Any?) { Settings.autosave.toggle() }
    @objc func goToFile(_ sender: Any?) { keyController?.showFilePicker() }
    @objc func searchRepo(_ sender: Any?) { keyController?.showRepoSearch() }
    @objc func goToDefinition(_ sender: Any?) { keyController?.goToDefinition() }
    @objc func goBackInHistory(_ sender: Any?) { keyController?.goBackInHistory() }
    @objc func goForwardInHistory(_ sender: Any?) { keyController?.goForwardInHistory() }
    @objc func toggleExplorer(_ sender: Any?) { keyController?.toggleExplorer() }
    @objc func explorerSearch(_ sender: Any?) { keyController?.focusExplorerSearch() }

    // Content type scale: app-global by design — every terminal and editor
    // in every window observes the token, so the chords never need a target.
    @objc func biggerText(_ sender: Any?) { Theme.TypeScale.bump(1) }
    @objc func smallerText(_ sender: Any?) { Theme.TypeScale.bump(-1) }
    @objc func resetTextSize(_ sender: Any?) { Theme.TypeScale.reset() }
    @objc func selectSession(_ sender: NSMenuItem) { keyController?.selectSession(number: sender.tag) }
    @objc func nextSession(_ sender: Any?) { keyController?.selectNext() }
    @objc func prevSession(_ sender: Any?) { keyController?.selectPrev() }

    @objc func focusLeft(_ sender: Any?) { keyController?.focusPane(.left) }
    @objc func focusDown(_ sender: Any?) { keyController?.focusPane(.down) }
    @objc func focusUp(_ sender: Any?) { keyController?.focusPane(.up) }
    @objc func focusRight(_ sender: Any?) { keyController?.focusPane(.right) }
}

extension AppDelegate: NSMenuItemValidation {
    /// "Reopen Closed Session" is only offered when there's something to reopen;
    /// every other item keeps its default enablement.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutosave(_:)) {
            menuItem.state = Settings.autosave ? .on : .off
            return true
        }
        if menuItem.action == #selector(newWorktreeSession(_:)) {
            return keyController?.canChooseWorktree ?? false
        }
        if menuItem.action == #selector(selectSession(_:)) {
            // Numbers past the last tab are greyed out, and their chords
            // do nothing.
            return menuItem.tag <= (keyController?.sessionCount ?? 0)
        }
        if menuItem.action == #selector(reopenSession(_:)) {
            return keyController?.canReopenClosedSession ?? false
        }
        if menuItem.action == #selector(openFile(_:)) || menuItem.action == #selector(goToFile(_:))
            || menuItem.action == #selector(searchRepo(_:)) {
            return keyController?.canUseEditor ?? false
        }
        if menuItem.action == #selector(saveFile(_:)) || menuItem.action == #selector(goToDefinition(_:)) {
            return keyController?.editorHasFile ?? false
        }
        return true
    }
}

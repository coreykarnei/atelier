import AppKit

/// Builds Atelier's main menu. A SwiftPM-bootstrapped app has no menu by default,
/// which means the standard Edit-menu actions (Copy/Paste/Select All) are never
/// wired into the responder chain — so Cmd-C does nothing.
///
/// This matters more than it looks: Cmd-C → `copy:` → the focused terminal view's
/// `copy(_:)` is the path that runs SwiftTerm's wrap-intent-aware `getSelectedText()`.
/// Without the menu, *truthful copy never fires*. The menu is the keystone that
/// connects the keyboard to the feature that justifies the project.
enum Menu {
    static func build() -> NSMenu {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Atelier", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Atelier", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Atelier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu (M2.1): the editor's open/save. Routed to AppDelegate →
        // key window; items disable outside an IDE session.
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        fileMenu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openFile(_:)), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Save", action: #selector(AppDelegate.saveFile(_:)), keyEquivalent: "s")
        fileMenu.addItem(.separator())
        // A checkmark item mirroring Settings → Autosave; validation sets the state.
        fileMenu.addItem(withTitle: "Autosave", action: #selector(AppDelegate.toggleAutosave(_:)), keyEquivalent: "")

        // Edit menu — this is the load-bearing one. nil targets route through the
        // responder chain to the focused terminal/editor view.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        // Undo/Redo reach the editor's CEUndoManager via the responder chain
        // (NSWindow asks the first responder for its undoManager).
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(chord("Redo", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu. Nil targets route through the responder chain to AppDelegate
        // (and, later, to the key window's controller).
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu

        viewMenu.addItem(withTitle: "Toggle Layout", action: #selector(AppDelegate.toggleLayout(_:)), keyEquivalent: "\\")
        viewMenu.addItem(chord("Command Palette…", #selector(AppDelegate.showPalette(_:)), "p", [.command, .shift]))
        viewMenu.addItem(withTitle: "Go to File…", action: #selector(AppDelegate.goToFile(_:)), keyEquivalent: "p")
        viewMenu.addItem(chord("Find in Repo…", #selector(AppDelegate.searchRepo(_:)), "f", [.command, .shift]))
        viewMenu.addItem(withTitle: "Toggle Explorer", action: #selector(AppDelegate.toggleExplorer(_:)), keyEquivalent: "b")
        // F12 — the VSCode instinct (§2.6). Function keys carry no modifier.
        viewMenu.addItem(chord("Go to Definition", #selector(AppDelegate.goToDefinition(_:)),
                               String(UnicodeScalar(UInt16(NSF12FunctionKey))!), []))
        viewMenu.addItem(.separator())

        viewMenu.addItem(withTitle: "New Project Tab", action: #selector(AppDelegate.newProject(_:)), keyEquivalent: "t")
        viewMenu.addItem(chord("Close Project", #selector(AppDelegate.closeProject(_:)), "w", [.command, .option]))
        viewMenu.addItem(chord("New Session…", #selector(AppDelegate.newSession(_:)), "t", [.command, .option]))
        viewMenu.addItem(withTitle: "Open IDE Here", action: #selector(AppDelegate.openIDEHere(_:)), keyEquivalent: "\r")
        viewMenu.addItem(withTitle: "Close Session", action: #selector(AppDelegate.closeSession(_:)), keyEquivalent: "w")
        // ⌘⇧T is the browser's reopen chord — muscle memory the close `×` earns.
        viewMenu.addItem(chord("Reopen Closed Session", #selector(AppDelegate.reopenSession(_:)), "t", [.command, .shift]))
        viewMenu.addItem(chord("Next Session", #selector(AppDelegate.nextSession(_:)), "]", [.command, .shift]))
        viewMenu.addItem(chord("Previous Session", #selector(AppDelegate.prevSession(_:)), "[", [.command, .shift]))
        viewMenu.addItem(chord("Next Project", #selector(AppDelegate.nextProject(_:)), "\t", [.control]))
        viewMenu.addItem(chord("Previous Project", #selector(AppDelegate.prevProject(_:)), "\t", [.control, .shift]))
        viewMenu.addItem(.separator())

        viewMenu.addItem(chord("Focus Left", #selector(AppDelegate.focusLeft(_:)), "h", [.command, .control]))
        viewMenu.addItem(chord("Focus Down", #selector(AppDelegate.focusDown(_:)), "j", [.command, .control]))
        viewMenu.addItem(chord("Focus Up", #selector(AppDelegate.focusUp(_:)), "k", [.command, .control]))
        viewMenu.addItem(chord("Focus Right", #selector(AppDelegate.focusRight(_:)), "l", [.command, .control]))
        viewMenu.addItem(.separator())

        // Content type scale — terminals + editor, every window (chrome
        // doesn't scale). ⌘= is the unshifted twin of ⌘+, hidden but live,
        // so the chord works without reaching for shift.
        viewMenu.addItem(withTitle: "Bigger Text", action: #selector(AppDelegate.biggerText(_:)), keyEquivalent: "+")
        let plusTwin = NSMenuItem(title: "Bigger Text", action: #selector(AppDelegate.biggerText(_:)), keyEquivalent: "=")
        plusTwin.isHidden = true
        plusTwin.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(plusTwin)
        viewMenu.addItem(withTitle: "Smaller Text", action: #selector(AppDelegate.smallerText(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: "Reset Text Size", action: #selector(AppDelegate.resetTextSize(_:)), keyEquivalent: "0")

        // Window menu. ⌘1..⌘9 focus the Nth project tab (MILESTONE_1 §5);
        // ⌃⇥ / ⌃⇧⇥ cycle them (View menu), as native tabs did.
        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(.separator())
        for n in 1...9 {
            let item = NSMenuItem(title: "Project \(n)", action: #selector(AppDelegate.selectProject(_:)), keyEquivalent: "\(n)")
            item.tag = n
            windowMenu.addItem(item)
        }

        return main
    }

    /// A menu item with a non-default modifier mask on its key equivalent.
    private static func chord(_ title: String, _ action: Selector, _ key: String, _ mask: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        return item
    }
}

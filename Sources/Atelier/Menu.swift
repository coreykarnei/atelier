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
        appMenu.addItem(withTitle: "Hide Atelier", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Atelier", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu — this is the load-bearing one. nil targets route through the
        // responder chain to the focused terminal/editor view.
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Cut", action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu. `⌘\` toggles the layout mode; the nil target routes through the
        // responder chain to AppDelegate (and, later, to the key window's controller).
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Toggle Layout", action: #selector(AppDelegate.toggleLayout(_:)), keyEquivalent: "\\")

        return main
    }
}

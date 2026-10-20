import AppKit
import UniformTypeIdentifiers

/// What a link click may open without asking (2026-10 security pass). A
/// terminal link can come from anything printed there, OSC 8 lets its text
/// say something other than where it goes, and a cloned repo's files carry
/// no quarantine, so Gatekeeper never looks at them. Web and mail links and
/// ordinary documents open as they always did. Anything that *runs* — an
/// app, an installer, a script, an executable, a file whose default app is a
/// terminal, a URL scheme only some other app understands — asks first,
/// saying exactly what it is (owner call 2026-10-20: ask, don't refuse).
enum LinkPolicy {
    /// Open `target` now, or after the user says so. `open` does the opening.
    static func open(_ target: URL, from view: NSView?, open: @escaping () -> Void) {
        guard let reason = reasonToAsk(target) else {
            open()
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        let name = target.isFileURL ? target.lastPathComponent : (target.scheme ?? "link")
        alert.messageText = "Open \u{201C}\(name)\u{201D}?"
        alert.informativeText = reason
        let place = target.isFileURL
            ? (target.path as NSString).abbreviatingWithTildeInPath
            : target.absoluteString
        let label = NSTextField(wrappingLabelWithString: place)
        label.font = Theme.Typography.mono(Theme.Typography.small)
        label.textColor = Theme.chromeText
        label.preferredMaxLayoutWidth = 320
        label.frame = NSRect(x: 0, y: 0, width: 320, height: label.fittingSize.height)
        alert.accessoryView = label
        let openButton = alert.addButton(withTitle: "Open")
        let cancel = alert.addButton(withTitle: "Cancel")
        // ↩ is the safe answer here; opening takes a click.
        openButton.keyEquivalent = ""
        cancel.keyEquivalent = "\r"
        if let window = view?.window {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { open() } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            open()
        }
    }

    /// Why `target` needs a yes first — the alert's sentence — or nil when
    /// it opens like any document or web page.
    static func reasonToAsk(_ target: URL) -> String? {
        guard target.isFileURL else {
            switch target.scheme?.lowercased() {
            case "http", "https", "mailto":
                return nil
            default:
                let app = handlerName(for: target).map { "\u{201C}\($0)\u{201D}" } ?? "another app"
                return "\(target.scheme ?? "This"): links open in \(app)."
            }
        }
        let keys: Set<URLResourceKey> = [.isApplicationKey, .isRegularFileKey, .isExecutableKey, .contentTypeKey]
        let values = try? target.resourceValues(forKeys: keys)
        let kind = values?.contentType?.localizedDescription ?? "file"
        if values?.isApplication == true {
            return "It's an application. Opening it runs it."
        }
        if runsWhenOpened.contains(target.pathExtension.lowercased()) {
            return "It's \(article(kind)) \(kind). Opening it can run it."
        }
        if values?.isRegularFile == true, values?.isExecutable == true {
            return "It's an executable file."
        }
        if let app = handlerID(for: target), runningHandlers.contains(app) {
            let name = handlerName(for: target) ?? "a terminal"
            return "It opens in \u{201C}\(name)\u{201D}, which runs it."
        }
        return nil
    }

    /// Extensions whose default action is to run, install or act — whatever
    /// app happens to claim them.
    private static let runsWhenOpened: Set<String> = [
        "app", "command", "tool", "terminal", "sh", "zsh", "bash",
        "pkg", "mpkg", "mobileconfig", "prefpane", "saver", "kext", "plugin",
        "workflow", "action", "scpt", "scptd", "applescript", "shortcut", "jar",
        "webloc", "inetloc", "fileloc",
    ]

    /// Apps that run what they open.
    private static let runningHandlers: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty",
        "com.apple.installer", "com.apple.systempreferences",
    ]

    private static func article(_ noun: String) -> String {
        "aeiou".contains(noun.lowercased().first ?? "x") ? "an" : "a"
    }

    private static func handlerID(for target: URL) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: target).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private static func handlerName(for target: URL) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: target).map {
            FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "")
        }
    }
}

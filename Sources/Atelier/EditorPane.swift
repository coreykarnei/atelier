import AppKit
import AtelierIPC
import CodeEditSourceEditor
import CodeEditTextView
import CodeEditLanguages

/// The editor pane (Milestone 2.1 — TECHNICAL_PLAN §3.3). Hosts
/// CodeEditSourceEditor's `TextViewController`: a TextKit 2 buffer with
/// incremental tree-sitter highlighting, themed to the same Catppuccin Mocha
/// the terminals speak (`Theme.Editor`), translucent over the window blur like
/// every other field surface.
///
/// With no file open it reads as the recessed well the placeholder was —
/// crust, below the content plane, waiting. `⌘O` opens a file (the `⌘P`
/// summon picker is M2.2); `⌘S` saves; edits mark the buffer dirty until
/// saved. The open file rides session persistence.
final class EditorPane: NSView, WorkspacePane {
    /// The committed buffer when there is one, else the tree — so ⌃⌘H lands
    /// somewhere useful before the first file opens. A preview is the tree's
    /// buffer; focus stays with the tree.
    var focusView: NSView {
        if let controller, !isPreview { return controller.textView }
        return explorerExpanded ? explorer.focusView : (controller?.textView ?? self)
    }
    override var acceptsFirstResponder: Bool { controller == nil }

    /// The tree down the left edge (M2.6). Opens route through the host so
    /// the dirty-buffer guard applies; `commit` distinguishes double-click/↩
    /// (open for real) from a single click (preview).
    let explorer = FileExplorerView(frame: .zero)
    var onOpenRequest: ((URL, _ commit: Bool) -> Void)?
    /// A text-search hit from the sidebar: open for real at the hit.
    var onOpenAtRequest: ((URL, SearchHit) -> Void)?
    /// Arrowing through sidebar search results: preview, optionally at a hit.
    var onPreviewRequest: ((URL, SearchHit?) -> Void)?
    /// Everything right of the tree: the empty-state line, then the header
    /// strip and the buffer (or, for markdown in Preview, the rendering).
    private let contentHost = NSView()
    private let fileHeader = EditorFileHeader()
    private let diagnosticStrip = DiagnosticStrip()
    /// The one wash under the buffer (2026-09-16). Translucent fields paint
    /// their alpha exactly once (the transparency devlog): this view is the
    /// single owner of the content region's colour — crust while the well is
    /// empty, base once a file is open — and everything above it (the
    /// library's scroll view and gutter, the markdown rendering) paints clear.
    /// Before this the pane's own crust layer sat under the buffer's base and
    /// the gutter's base again: two or three 0.75 coats compounding to ~0.94,
    /// which is why the editor read denser than the terminals beside it.
    private let contentWash = NSView()
    private var washTopFull: NSLayoutConstraint!
    private var washTopBelowHeader: NSLayoutConstraint!

    // MARK: File history (2026-09-16)
    // Where you've been, in order — committed opens only (previews are
    // glances). ⌘-click into a `.pyi` and `<` brings you straight back to
    // the line you left. Capped; a session isn't a browser.
    private struct HistoryEntry { let path: String; var line: Int }
    private var history: [HistoryEntry] = []
    private var historyIndex = -1
    /// Fired when back/forward availability changes.
    var onHistoryChange: (() -> Void)?
    /// History navigation asks the controller to open (dirty guard, focus)
    /// rather than opening directly.
    var onNavigateRequest: ((_ path: String, _ line: Int, _ column: Int) -> Void)?
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }

    /// The current entry learns the caret line the moment we leave it.
    private func rememberPosition() {
        guard historyIndex >= 0, let filePath, history[historyIndex].path == filePath else { return }
        history[historyIndex].line = cursorPosition?.line ?? 1
    }

    private func recordVisit(_ path: String) {
        if historyIndex >= 0, history[historyIndex].path == path { return }
        history = Array(history.prefix(historyIndex + 1))
        history.append(HistoryEntry(path: path, line: cursorPosition?.line ?? 1))
        if history.count > 100 { history.removeFirst(history.count - 100) }
        historyIndex = history.count - 1
        fileHeader.setHistory(back: canGoBack, forward: canGoForward)
        onHistoryChange?()
    }

    func goBack() { navigateHistory(by: -1) }
    func goForward() { navigateHistory(by: 1) }

    private func navigateHistory(by step: Int) {
        rememberPosition()
        var target = historyIndex + step
        // Files vanish (worktree torn down, stash): drop dead entries and
        // keep stepping the same way.
        while target >= 0, target < history.count,
              !FileManager.default.fileExists(atPath: history[target].path) {
            history.remove(at: target)
            if step < 0 { target -= 1; historyIndex -= 1 }
        }
        guard target >= 0, target < history.count else {
            fileHeader.setHistory(back: canGoBack, forward: canGoForward)
            onHistoryChange?()
            return
        }
        historyIndex = target
        let entry = history[target]
        fileHeader.setHistory(back: canGoBack, forward: canGoForward)
        onHistoryChange?()
        onNavigateRequest?(entry.path, entry.line, 1)
    }
    private let preview = MarkdownPreviewView(frame: .zero)
    private var previewRenderDebounce: Timer?
    private var isMarkdown: Bool { bufferLanguage?.id == .markdown }
    private static let previewKey = "editor.markdownPreview"
    /// Markdown opens in the mode you last chose (Text by default).
    private var previewMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.previewKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.previewKey) }
    }
    private var contentLeading: NSLayoutConstraint!
    private var explorerWidth: NSLayoutConstraint!
    /// Wide (browsing) or folded to the rail (a file is open for real).
    private var explorerExpanded = true
    /// The buffer is a click-preview: soft-wrapped, tree wide, not yet the
    /// session's file — persistence and the language server ignore it, and
    /// the buffer is **read-only** (hardened 2026-09-16, owner report: ⌘X
    /// cut text out of a preview without the file ever being entered). A
    /// glance lets you scroll, select and copy; nothing can mutate it. You
    /// *enter* the file — unwrap, fold the tree, tell the server — by one of
    /// exactly these: double-click/↩ in the tree, double-click in the buffer,
    /// or an editing keystroke into the buffer (typing, ⌫, ⌘X/⌘V, the
    /// chords), which enters first and then applies. See `enterPreview`.
    private(set) var isPreview = false
    /// Soft-wrap follows the preview in, and leaves on a gesture commit only.
    private var isWrapped = false
    /// What the session persists: the committed file only.
    var committedFilePath: String? { isPreview ? nil : filePath }

    /// Absolute path of the open file, nil when the well is empty.
    private(set) var filePath: String?
    /// Unsaved edits exist. Owner is told on change (future tab/gutter marks).
    private(set) var isDirty = false {
        didSet {
            if oldValue != isDirty {
                onDirtyChange?(isDirty)
                fileHeader.isDirty = isDirty
            }
        }
    }
    var onDirtyChange: ((Bool) -> Void)?

    private var controller: TextViewController?
    private let changeCoordinator = ChangeCoordinator()
    private let emptyLabel = NSTextField(labelWithString: "")

    /// The repo root whose language server this buffer reports to (M2.5).
    /// Set by the session before any open; Swift files get didOpen/didChange/
    /// didSave and diagnostics underlines, other languages stay plain.
    var lspRoot: String?
    private var lspClient: LSPClient? {
        guard let lspRoot, let language = bufferLanguage, !isPreview else { return nil }
        return LSPRegistry.client(for: lspRoot, language: language)
    }
    /// The committed buffer's server, for the host's definition requests.
    var bufferLSPClient: LSPClient? { lspClient }
    private var bufferLanguage: CodeLanguage?
    private var lspChangeDebounce: Timer?
    private var autosaveDebounce: Timer?
    /// The open file's on-disk watcher (M2.6): stash, agent, formatter — any
    /// outside write reloads a clean buffer in place. See `watchFile`.
    private var fileWatch: DispatchSourceFileSystemObject?
    private var fileReloadDebounce: Timer?
    /// Clips the text view to the right of the gutter: the gutter floats
    /// over the text, translucent like the pane, so text scrolled under it
    /// showed through the line numbers. An opaque gutter would kill the blur
    /// in that strip; masking the text is the honest fix.
    private let gutterMask = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Clear: the tree washes its own strip, `contentWash` the rest.
        layer?.backgroundColor = NSColor.clear.cgColor
        buildChrome()
        buildEmptyState()
        explorer.onOpen = { [weak self] url, commit in self?.onOpenRequest?(url, commit) }
        explorer.onToggle = { [weak self] in self?.toggleExplorer() }
        explorer.onOpenAt = { [weak self] url, hit in self?.onOpenAtRequest?(url, hit) }
        explorer.onPreview = { [weak self] url, hit in self?.onPreviewRequest?(url, hit) }
        explorer.onRenamed = { [weak self] from, to in self?.fileRenamed(from: from, to: to) }
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: Settings.didChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(typeScaleChanged),
            name: Theme.TypeScale.didChange,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        stopWatchingFile()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// ⌘+/⌘−/⌘0 — the buffer rides the same content scale as the terminals.
    @objc private func typeScaleChanged() {
        controller?.configuration = Self.configuration(wrap: isWrapped)
        if !preview.isHidden, let controller { preview.render(markdown: controller.text) }
    }

    override func updateLayer() {
        applyWash()
    }

    @objc private func accessibilityDisplayChanged() {
        applyWash()
        layoutExplorer()
    }

    /// The content region's one coat: the recessed well (crust) until a file
    /// is open, then the field (base). Re-read on every fieldAlpha change.
    private func applyWash() {
        let color = fileHeader.isHidden ? Theme.Elevation.crust : Theme.Elevation.base
        contentWash.layer?.backgroundColor = color.cgColor
    }

    /// The header strip paints its own mantle, so the wash starts under it
    /// when it's shown — one coat per pixel, never two.
    private func setFileHeaderVisible(_ visible: Bool) {
        fileHeader.isHidden = !visible
        washTopFull.isActive = !visible
        washTopBelowHeader.isActive = visible
        applyWash()
    }

    /// Tree on the left, content host filling the rest. The tree is wide
    /// while browsing, a rail once a file is open for real, absent before a
    /// root exists.
    private func buildChrome() {
        explorer.translatesAutoresizingMaskIntoConstraints = false
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(explorer)
        addSubview(contentHost)
        contentLeading = contentHost.leadingAnchor.constraint(equalTo: leadingAnchor)
        explorerWidth = explorer.widthAnchor.constraint(equalToConstant: FileExplorerView.width)
        contentWash.wantsLayer = true
        contentWash.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(contentWash) // first in, so it sits under everything
        fileHeader.translatesAutoresizingMaskIntoConstraints = false
        fileHeader.isHidden = true
        fileHeader.onBack = { [weak self] in self?.goBack() }
        fileHeader.onForward = { [weak self] in self?.goForward() }
        fileHeader.onModeChange = { [weak self] previewOn in
            guard let self else { return }
            self.previewMode = previewOn
            self.applyViewMode()
        }
        contentHost.addSubview(fileHeader)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isHidden = true
        contentHost.addSubview(preview)
        diagnosticStrip.translatesAutoresizingMaskIntoConstraints = false
        diagnosticStrip.isHidden = true
        contentHost.addSubview(diagnosticStrip)
        washTopFull = contentWash.topAnchor.constraint(equalTo: contentHost.topAnchor)
        washTopBelowHeader = contentWash.topAnchor.constraint(equalTo: fileHeader.bottomAnchor)
        NSLayoutConstraint.activate([
            contentWash.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            contentWash.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            contentWash.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            washTopFull,
            fileHeader.topAnchor.constraint(equalTo: contentHost.topAnchor),
            fileHeader.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            fileHeader.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            fileHeader.heightAnchor.constraint(equalToConstant: EditorFileHeader.height),
            preview.topAnchor.constraint(equalTo: fileHeader.bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            preview.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            diagnosticStrip.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            diagnosticStrip.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            diagnosticStrip.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ])
        NSLayoutConstraint.activate([
            explorer.topAnchor.constraint(equalTo: topAnchor),
            explorer.leadingAnchor.constraint(equalTo: leadingAnchor),
            explorer.bottomAnchor.constraint(equalTo: bottomAnchor),
            explorerWidth,
            contentHost.topAnchor.constraint(equalTo: topAnchor),
            contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentLeading,
        ])
        layoutExplorer()
        applyWash()
    }

    private func layoutExplorer() {
        let hasRoot = explorer.root != nil
        explorer.isHidden = !hasRoot
        explorer.setCollapsed(!explorerExpanded)
        let width = !hasRoot ? 0 : (explorerExpanded ? FileExplorerView.width : FileExplorerView.railWidth)
        explorerWidth.constant = width
        contentLeading.constant = width
    }

    /// The session's directory: what the tree shows and what the language
    /// server is scoped to. Set on promote/restore, before any open.
    func setRoot(_ root: String) {
        lspRoot = root
        explorer.setRoot(root)
        layoutExplorer()
    }

    /// ⌘⇧E — the sidebar's search panel, tree unfolded if it was a rail.
    func focusExplorerSearch() {
        guard explorer.root != nil else { return }
        setExplorerExpanded(true)
        explorer.openSearch()
    }

    /// Dev-only: unfold the tree and hand the query to the explorer's driver.
    /// `probe:dupundo` instead exercises ⇧⌥↓ then ⌘Z on the buffer and
    /// writes what happened to ~/.local/state/atelier/probe.txt.
    func debugExplorer(_ query: String) {
        if query.hasPrefix("probe:diag=") {
            // `probe:diag=/path:L:C` — open committed, park the caret, and
            // after the server has had 4s report diagnostics + strip state.
            let spec = String(query.dropFirst("probe:diag=".count)).split(separator: ":").map(String.init)
            guard spec.count == 3, let line = Int(spec[1]), let column = Int(spec[2]) else { return }
            try? open(path: spec[0], preview: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                guard let self else { return }
                self.reveal(line: line, column: column)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let report = "root=\(self.lspRoot ?? "-") diagnostics=\(self.lastDiagnostics.count) "
                        + self.lastDiagnostics.prefix(5).map { "\($0.startLine + 1):\($0.startCharacter + 1)-\($0.endLine + 1):\($0.endCharacter + 1) \($0.severity) '\($0.message.prefix(60))'" }.joined(separator: " | ")
                        + "\nstrip hidden=\(self.diagnosticStrip.isHidden) text='\(self.diagnosticStrip.debugText)' frame=\(self.diagnosticStrip.frame)\n"
                    try? report.write(toFile: NSHomeDirectory() + "/.local/state/atelier/probe.txt", atomically: true, encoding: .utf8)
                }
            }
            return
        }
        if query.hasPrefix("probe:links=") {
            let word = String(query.dropFirst("probe:links=".count))
            guard let controller else { return }
            let range = (controller.text as NSString).range(of: word)
            guard range.location != NSNotFound else { return }
            Task { @MainActor in
                let links = await self.queryLinks(forRange: range, textView: controller) ?? []
                let report = "links for '\(word)': \(links.count) " + links.map { "\($0.url?.lastPathComponent ?? "same-file"):\($0.targetRange.start.line):\($0.targetRange.start.column)" }.joined(separator: " ") + "\n"
                try? report.write(toFile: NSHomeDirectory() + "/.local/state/atelier/probe.txt", atomically: true, encoding: .utf8)
            }
            return
        }
        if query.hasPrefix("probe:resize=") {
            // `probe:resize=W,H` — the window, from its top-left; layout bugs
            // on resize reproduce without a pointer.
            let parts = query.dropFirst("probe:resize=".count).split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2, let window else { return }
            var frame = window.frame
            frame.origin.y = frame.maxY - parts[1]
            frame.size = NSSize(width: parts[0], height: parts[1])
            window.setFrame(frame, display: true, animate: false)
            return
        }
        if query.hasPrefix("probe:preview=") {
            // `probe:preview=/path` — a tree-click preview, without a pointer.
            try? open(path: String(query.dropFirst("probe:preview=".count)), preview: true)
            return
        }
        if query.hasPrefix("probe:enter=") {
            // `probe:enter=<gesture>` — aim a gesture at the preview buffer
            // and report the boundary's state ~0.5s later. Gestures: `cut`
            // (select 3 chars, ⌘X), `type` (a plain "q"), `paste` (⌘V),
            // `arrow` (↓ — must not enter), `copy` (⌘C — must not enter),
            // `dblclick` (a two-click mouseDown in the buffer's centre).
            let gesture = String(query.dropFirst("probe:enter=".count))
            guard let controller, let window, let textView = controller.textView else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            let before = controller.text
            func key(_ chars: String, _ code: UInt16, _ mods: NSEvent.ModifierFlags) {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                        isARepeat: false, keyCode: code
                    ) { NSApp.sendEvent(event) }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                switch gesture {
                case "cut":
                    controller.setCursorPositions([CursorPosition(range: NSRange(location: 0, length: 3))])
                    key("x", 7, [.command])
                case "type": key("q", 12, [])
                case "paste": key("v", 9, [.command])
                case "copy":
                    controller.setCursorPositions([CursorPosition(range: NSRange(location: 0, length: 3))])
                    key("c", 8, [.command])
                case "arrow":
                    key(String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!), 125, [.function, .numericPad])
                case "dblclick":
                    // Posted, not sent: only an event pulled from the queue
                    // becomes `NSApp.currentEvent`, which the real detection
                    // reads. Aimed at the first line, past the gutter.
                    let point = textView.convert(NSPoint(x: 80, y: textView.visibleRect.minY + 8), to: nil)
                    for count in 1...2 {
                        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                            if let event = NSEvent.mouseEvent(
                                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1
                            ) { NSApp.postEvent(event, atStart: false) }
                        }
                    }
                default: break
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let report = "gesture=\(gesture) preview=\(self.isPreview) wrapped=\(self.isWrapped) "
                        + "editable=\(textView.isEditable) explorerExpanded=\(self.explorerExpanded) "
                        + "textChanged=\(controller.text != before) len=\(before.count)->\(controller.text.count) "
                        + "selection=\(controller.cursorPositions.first.map { "\($0.range)" } ?? "none") "
                        + "fr=\(window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil") "
                        + "pasteboard='\(NSPasteboard.general.string(forType: .string)?.prefix(12) ?? "")'\n"
                    try? report.write(toFile: AtelierIPC.stateDirectory() + "/probe.txt", atomically: true, encoding: .utf8)
                }
            }
            return
        }
        if query.hasPrefix("probe:key=") {
            // `probe:key=<char>[,cmd][,shift][,opt][,ctrl]` — one keystroke
            // posted to the queue (menus and modal alerts included). `\r`
            // for ↩, `\e` for esc.
            let parts = query.dropFirst("probe:key=".count).split(separator: ",").map(String.init)
            guard let first = parts.first, let window else { return }
            var mods: NSEvent.ModifierFlags = []
            if parts.contains("cmd") { mods.insert(.command) }
            if parts.contains("shift") { mods.insert(.shift) }
            if parts.contains("opt") { mods.insert(.option) }
            if parts.contains("ctrl") { mods.insert(.control) }
            let chars = first == "\\r" ? "\r" : first == "\\e" ? "\u{1b}" : first
            let code: UInt16 = chars == "\r" ? 36 : chars == "\u{1b}" ? 53 : 0
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                if let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                    isARepeat: false, keyCode: code
                ) { NSApp.postEvent(event, atStart: false) }
            }
            return
        }
        if query == "probe:back" { goBack(); return }
        if query == "probe:forward" { goForward(); return }
        if query.hasPrefix("probe:findseed=") {
            // `probe:findseed=word` — select the first occurrence, press ⌘F.
            let word = String(query.dropFirst("probe:findseed=".count))
            guard let controller, let window, let textView = controller.textView else { return }
            let range = (controller.text as NSString).range(of: word)
            guard range.location != NSNotFound else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            controller.setCursorPositions([CursorPosition(range: range)], scrollToVisible: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: [.command], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: "f", charactersIgnoringModifiers: "f",
                        isARepeat: false, keyCode: 3
                    ) { NSApp.sendEvent(event) }
                }
            }
            return
        }
        if query == "probe:keys" {
            // The real path: synthesized key events through NSApp.sendEvent —
            // the library's local monitor, then the menu's key equivalent.
            if controller == nil {
                let scratch = NSTemporaryDirectory() + "atelier-probe.md"
                try? "alpha\nbeta\ngamma\n".write(toFile: scratch, atomically: true, encoding: .utf8)
                try? open(path: scratch)
                reveal(line: 2, column: 1)
            }
            guard let controller, let window, let textView = controller.textView else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak controller, weak window, weak textView] in
            guard let self, let controller, let window, let textView else { return }
            _ = self
            window.makeFirstResponder(textView)
            var log: [String] = []
            func fr() -> String { window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil" }
            func key(_ chars: String, _ code: UInt16, _ mods: NSEvent.ModifierFlags) {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(
                        with: type, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                        isARepeat: false, keyCode: code
                    ) { NSApp.sendEvent(event) }
                    log.append("\(type == .keyDown ? "down" : "up")(\(code)) fr=\(fr()) len=\(controller.text.count)")
                }
            }
            log.append("start fr=\(fr())")
            TextViewController.debugTrace = { line in log.append("  lib: " + line) }
            TextView.debugTrace = { line in log.append("  lib: " + line) }
            defer { TextViewController.debugTrace = nil; TextView.debugTrace = nil }
            let before = controller.text
            key(String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!), 125, [.shift, .option, .function, .numericPad])
            let after = controller.text
            key("z", 6, [.command])
            let undone = controller.text
            let report = "keys: before=\(before.count) after=\(after.count) undone=\(undone.count) restored=\(undone == before) "
                + "key=\(window.isKeyWindow) canUndo=\(textView.undoManager?.canUndo ?? false)\n" + log.joined(separator: "\n") + "\n"
            try? report.write(toFile: NSHomeDirectory() + "/.local/state/atelier/probe.txt", atomically: true, encoding: .utf8)
            }
            return
        }
        if query == "probe:steps" {
            guard let controller, let window, let textView = controller.textView else { return }
            window.makeFirstResponder(textView)
            var log: [String] = []
            func fr() -> String { window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil" }
            log.append("start fr=\(fr())")
            textView.undoManager?.beginUndoGrouping()
            log.append("begin fr=\(fr())")
            let len = (controller.text as NSString).length
            textView.replaceCharacters(in: [NSRange(location: len, length: 0)], with: "delta\n")
            log.append("replace fr=\(fr())")
            controller.setCursorPositions([CursorPosition(range: NSRange(location: len, length: 5))], scrollToVisible: true)
            log.append("setCursor fr=\(fr())")
            textView.undoManager?.endUndoGrouping()
            log.append("end fr=\(fr())")
            controller.duplicateLines(above: false)
            log.append("dupDirect fr=\(fr())")
            try? (log.joined(separator: "\n") + "\n").write(toFile: NSHomeDirectory() + "/.local/state/atelier/probe.txt", atomically: true, encoding: .utf8)
            return
        }
        if query == "probe:dupundo" {
            if controller == nil {
                let scratch = NSTemporaryDirectory() + "atelier-probe.md"
                try? "alpha\nbeta\ngamma\n".write(toFile: scratch, atomically: true, encoding: .utf8)
                try? open(path: scratch)
                reveal(line: 2, column: 1)
            }
            guard let controller else { return }
            let before = controller.text
            controller.duplicateLines(above: false)
            let after = controller.text
            controller.textView?.undoManager?.undo()
            let undone = controller.text
            let report = "before=\(before.count) after=\(after.count) undone=\(undone.count) restored=\(undone == before) "
                + "undoManager=\(controller.textView?.undoManager.map { String(describing: type(of: $0)) } ?? "nil") canUndo=\(controller.textView?.undoManager?.canUndo ?? false)\n"
            try? report.write(toFile: NSHomeDirectory() + "/.local/state/atelier/probe.txt", atomically: true, encoding: .utf8)
            return
        }
        setExplorerExpanded(true)
        explorer.debugSetQuery(query)
    }

    /// ⌘B / the chevron — unfold the tree or fold it to the rail.
    func toggleExplorer() {
        setExplorerExpanded(!explorerExpanded)
    }

    private func setExplorerExpanded(_ expanded: Bool) {
        guard expanded != explorerExpanded else { return }
        explorerExpanded = expanded
        layoutExplorer()
        if !expanded, window?.firstResponder === explorer.focusView {
            window?.makeFirstResponder(focusView)
        }
    }

    private func buildEmptyState() {
        // Two-voice (§1.4): the chord is mono, Atelier's sentence is ui.
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "⌘P", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body),
            .foregroundColor: Theme.chromeText,
        ]))
        line.append(NSAttributedString(string: " go to file", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeMutedText,
        ]))
        emptyLabel.attributedStringValue = line
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: contentHost.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentHost.centerYAnchor),
        ])
    }

    // MARK: Open / save

    /// Open `path` into the buffer, detecting its language. The first open
    /// builds the editor; later opens reuse it. Any unsaved edits in the
    /// previous file are the caller's problem to guard.
    ///
    /// `preview` (a tree click): soft-wrapped, tree stays wide, nothing told
    /// to the server or to persistence until you either commit by gesture
    /// (double-click/↩: unwrap, fold the tree) or simply start typing.
    /// Committing the same path afterwards flips configuration only — the
    /// text doesn't reload.
    func open(path: String, preview: Bool = false) throws {
        // Clicking the file that's already here changes nothing — a committed
        // buffer must not fall back to a read-only preview of itself.
        if preview, filePath == path { return }
        if !preview, filePath == path, isPreview || isWrapped {
            commitPreview()
            return
        }

        let url = URL(fileURLWithPath: path)
        let text = try String(contentsOf: url, encoding: .utf8)
        let language = CodeLanguage.detectLanguageFrom(url: url)

        // The previous buffer leaves the server's world before the new one
        // enters it; its underlines go with it.
        if let previous = filePath, previous != path {
            rememberPosition()
            lspClient?.didClose(path: previous)
            clearDiagnostics()
        }
        isPreview = preview
        isWrapped = preview

        if let controller {
            controller.configuration = Self.configuration(wrap: preview)
            controller.language = language
            controller.text = text
        } else {
            let controller = TextViewController(
                string: text,
                language: language,
                configuration: Self.configuration(wrap: preview),
                cursorPositions: [CursorPosition(line: 1, column: 1)],
                coordinators: [changeCoordinator]
            )
            changeCoordinator.onTextChange = { [weak self] in self?.bufferChanged() }
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(controller.view) // loads the view; the scroll view exists from here
            // Free two-axis scrolling: with wrapping off a code view is a plane,
            // and AppKit's axis lock makes diagonal trackpad gestures stutter.
            controller.scrollView?.usesPredominantAxisScrolling = false
            // The library gives the scroll view the theme background (alpha 0
            // here) but leaves it *drawing* one — AppKit then composites the
            // clip opaque. Off, so the pane's `contentWash` shows through.
            controller.scrollView?.drawsBackground = false
            // macOS 14 stopped clipping subviews by default; the gutter is a
            // floating subview sized to the whole document, so its line
            // numbers were painting up over the file header.
            controller.view.clipsToBounds = true
            controller.scrollView?.clipsToBounds = true
            installGutterMask(controller)
            controller.jumpToDefinitionDelegate = self
            controller.linkHoverColor = Theme.accentBlue
            contentHost.addSubview(diagnosticStrip, positioned: .above, relativeTo: controller.view)
            NotificationCenter.default.addObserver(
                self, selector: #selector(caretMoved),
                name: TextSelectionManager.selectionChangedNotification,
                object: controller.textView?.selectionManager as Any?
            )
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: fileHeader.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            ])
            self.controller = controller
        }
        // The boundary: a preview cannot be mutated by any path — key, menu,
        // drag-drop, chord — until it's entered (`enterPreview`).
        controller?.textView?.isEditable = !preview
        filePath = path
        isDirty = false // the coordinator saw the programmatic setText; undo it
        emptyLabel.isHidden = true
        explorer.reveal(path: path)
        bufferLanguage = language
        watchFile(path)
        setFileHeaderVisible(true)
        fileHeader.configure(name: displayName(for: path), markdown: isMarkdown, previewOn: isMarkdown && previewMode)
        applyViewMode()

        if !preview {
            recordVisit(path)
            announceOpen(path: path, text: text)
            setExplorerExpanded(false)
        }
    }

    // MARK: Gutter clip

    private func installGutterMask(_ controller: TextViewController) {
        guard let scrollView = controller.scrollView else { return }
        gutterMask.backgroundColor = NSColor.black.cgColor
        controller.textView?.layer?.mask = gutterMask
        NotificationCenter.default.addObserver(
            self, selector: #selector(gutterGeometryChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(gutterGeometryChanged),
            name: NSView.frameDidChangeNotification, object: controller.textView as Any?
        )
        updateGutterMask()
    }

    @objc private func gutterGeometryChanged() { updateGutterMask() }

    private func updateGutterMask() {
        guard let controller, let clip = controller.scrollView?.contentView,
              let textView = controller.textView else { return }
        // The gutter is the library's floating subview; find it by type so
        // the width follows its own line-count sizing.
        func gutter(in view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "GutterView" { return view }
            for sub in view.subviews { if let hit = gutter(in: sub) { return hit } }
            return nil
        }
        let gutterWidth = gutter(in: controller.view).map { $0.isHidden ? 0 : $0.frame.width } ?? 0
        let visibleX = clip.bounds.origin.x
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gutterMask.frame = CGRect(
            x: visibleX + gutterWidth, y: 0,
            width: max(0, textView.bounds.width - visibleX - gutterWidth), height: textView.bounds.height
        )
        CATransaction.commit()
    }

    /// The open file moved (tree rename). The buffer keeps its text and
    /// follows the path: watcher re-armed, server told, tree reselected.
    private func fileRenamed(from: String, to: String) {
        guard filePath == from, let controller else { return }
        lspClient?.didClose(path: from)
        filePath = to
        watchFile(to)
        explorer.reveal(path: to, scroll: false)
        fileHeader.configure(name: displayName(for: to), markdown: isMarkdown, previewOn: isMarkdown && previewMode)
        if !isPreview { announceOpen(path: to, text: controller.text) }
    }

    // MARK: On-disk changes

    /// Follow the file with a vnode source. Git and most editors replace a
    /// file by rename, which kills the descriptor's identity — so on any
    /// rename/delete the watch re-arms on the path once the new file is
    /// there. Events coalesce over a short debounce.
    private func watchFile(_ path: String) {
        stopWatchingFile()
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) || events.contains(.revoke) {
                // The inode is gone; the path may already carry its successor.
                self.stopWatchingFile()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, self.filePath == path else { return }
                    self.watchFile(path)
                    self.scheduleReloadFromDisk()
                }
                return
            }
            self.scheduleReloadFromDisk()
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        fileWatch = source
    }

    private func stopWatchingFile() {
        fileWatch?.cancel()
        fileWatch = nil
    }

    private func scheduleReloadFromDisk() {
        fileReloadDebounce?.invalidate()
        fileReloadDebounce = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
            self?.reloadFromDiskIfClean()
        }
    }

    /// The file changed under us. A clean buffer takes the new text, keeping
    /// caret and scroll where they were. A dirty buffer keeps your edits —
    /// nothing is thrown away silently; the next save wins.
    private func reloadFromDiskIfClean() {
        guard let controller, let filePath, !isDirty,
              let text = try? String(contentsOfFile: filePath, encoding: .utf8),
              text != controller.text else { return }
        let cursors = controller.cursorPositions
        let origin = controller.scrollView?.contentView.bounds.origin
        controller.text = text
        isDirty = false
        if !cursors.isEmpty { controller.setCursorPositions(cursors) }
        if let origin, let clip = controller.scrollView?.contentView {
            clip.scroll(to: origin)
            controller.scrollView?.reflectScrolledClipView(clip)
        }
        if !isPreview, let client = lspClient {
            client.didChange(path: filePath, text: text)
            client.requestDiagnostics(path: filePath)
        }
    }

    /// Preview → real: same text, unwrapped, editable, the server learns of
    /// it, the tree folds away. Reached by double-click/↩ in the tree, the
    /// search bar, or one of the buffer gestures in `enterPreview`.
    private func commitPreview() {
        guard let controller, let filePath else { return }
        let wasPreview = isPreview
        isPreview = false
        isWrapped = false
        controller.configuration = Self.configuration(wrap: false)
        controller.textView?.isEditable = true
        if wasPreview { announceOpen(path: filePath, text: controller.text) }
        recordVisit(filePath)
        setExplorerExpanded(false)
    }

    // MARK: Entering a preview from the buffer

    /// An editing keystroke into a read-only preview enters the file and
    /// then applies: the buffer is committed, and the very same event is
    /// re-sent through `NSApp` on the next turn so it takes the ordinary
    /// path — the library's key monitor, the menu's key equivalents, the
    /// (now editable) text view — as if you had typed it into the file.
    private func enterPreview(replaying event: NSEvent) {
        commitPreview()
        // Give the window a chance to settle the reconfigured view; a
        // synchronous re-send would nest inside the dispatch we're in.
        DispatchQueue.main.async { NSApp.sendEvent(event) }
    }

    /// Only the preview's own text view counts: keys aimed at the tree, the
    /// search field or a terminal never enter anything.
    private var previewBufferIsFirstResponder: Bool {
        guard isPreview, let textView = controller?.textView, let window else { return false }
        return window.firstResponder === textView
    }

    /// A key that would insert or delete text: printable characters, ⌫ ⌦ ↩
    /// ⇥, no ⌘/⌃. Navigation (arrows, page, home/end, esc) is not editing
    /// and moves nothing in a preview — it doesn't enter the file.
    private static func isEditingKey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !mods.contains(.command), !mods.contains(.control),
              let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        if scalar.value == UInt32(NSDeleteFunctionKey) { return true } // ⌦
        // The function-key plane (arrows, F-keys, page/home/end) is navigation.
        return !(0xF700...0xF8FF).contains(scalar.value)
    }

    /// The ⌘/⌥ chords that edit: cut, paste, comment, indent, move and
    /// duplicate lines. Copy, select-all, find, add-caret are not edits.
    private static func isEditingChord(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting([.function, .numericPad])
        let chars = event.charactersIgnoringModifiers ?? ""
        if mods == [.command] { return ["x", "v", "/", "[", "]"].contains(chars) }
        let vertical = [String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!),
                        String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)]
        if vertical.contains(chars) { return mods == [.option] || mods == [.option, .shift] }
        return false
    }

    /// Typing reaches here because the read-only text view passed the key
    /// up the responder chain (its `keyDown` only interprets when editable).
    override func keyDown(with event: NSEvent) {
        if previewBufferIsFirstResponder, Self.isEditingKey(event) {
            enterPreview(replaying: event)
            return
        }
        super.keyDown(with: event)
    }

    /// Key equivalents are offered to the view tree before the menu bar, so
    /// ⌘X/⌘V into a preview are caught here — before Edit → Cut would reach
    /// the read-only text view and do nothing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if previewBufferIsFirstResponder, Self.isEditingChord(event) {
            enterPreview(replaying: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Double-click in the buffer enters the file (owner ask 2026-09-16),
    /// the word it selected staying selected. Detected off the selection
    /// change the library's word-select makes synchronously inside the
    /// click's `mouseDown`, so the current event is that click.
    private func enterPreviewIfDoubleClicked() {
        guard isPreview, let textView = controller?.textView,
              let event = NSApp.currentEvent, event.type == .leftMouseDown, event.clickCount == 2,
              let window, event.windowNumber == window.windowNumber,
              textView.bounds.contains(textView.convert(event.locationInWindow, from: nil)) else { return }
        commitPreview()
    }

    // MARK: Header + markdown preview

    /// The path relative to the root when it's inside it, else the name.
    private func displayName(for path: String) -> String {
        if let lspRoot, path.hasPrefix(lspRoot + "/") { return String(path.dropFirst(lspRoot.count + 1)) }
        return (path as NSString).lastPathComponent
    }

    /// Text or Preview: the rendering stands in for the buffer for markdown
    /// files in Preview; everything else is the buffer.
    private func applyViewMode() {
        let showPreview = isMarkdown && previewMode && controller != nil
        preview.isHidden = !showPreview
        controller?.view.isHidden = showPreview
        if showPreview, let controller { preview.render(markdown: controller.text) }
    }

    private func schedulePreviewRender() {
        guard !preview.isHidden, let controller else { return }
        previewRenderDebounce?.invalidate()
        previewRenderDebounce = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self, weak controller] _ in
            guard let self, let controller else { return }
            self.preview.render(markdown: controller.text)
        }
    }

    /// Tell the language server a real buffer exists (Swift only).
    private func announceOpen(path: String, text: String) {
        guard let client = lspClient else { return }
        client.onDiagnostics = { [weak self] diagnosticsPath, diagnostics in
            guard let self, diagnosticsPath == self.filePath else { return }
            self.showDiagnostics(diagnostics)
        }
        client.didOpen(path: path, text: text)
        client.requestDiagnostics(path: path)
    }

    /// Every edit: dirty for the host, debounced didChange for the server
    /// (full-document sync — the buffer is small and the protocol allows it).
    private func bufferChanged() {
        isDirty = true
        clearHitMark()
        schedulePreviewRender()
        if isPreview {
            // A preview is read-only, so no edit should reach here; if one
            // ever does (a library path that skips `isEditable`), entering
            // the file is the only honest response — the text has changed.
            NSLog("Atelier: a preview buffer was mutated; entering the file")
            commitPreview()
        }
        if Settings.autosave, !isPreview {
            autosaveDebounce?.invalidate()
            autosaveDebounce = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
                guard let self, self.isDirty else { return }
                do { try self.save() } catch { NSLog("Atelier: autosave failed: \(error)") }
            }
        }
        guard lspClient != nil else { return }
        lspChangeDebounce?.invalidate()
        lspChangeDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self, let path = self.filePath, let text = self.controller?.text else { return }
            self.lspClient?.didChange(path: path, text: text)
            self.lspClient?.requestDiagnostics(path: path)
        }
    }

    /// Put the caret at `line:column` (1-indexed) and scroll it into view —
    /// how a search hit lands (M2.3). `highlightLength` marks that many
    /// characters from the caret the way ⌘F marks a match, so a hit reads
    /// even while the buffer isn't focused; the mark clears on the next edit
    /// or reveal.
    func reveal(line: Int, column: Int, highlightLength: Int? = nil) {
        guard let controller else { return }
        controller.setCursorPositions([CursorPosition(line: line, column: column)], scrollToVisible: true)
        clearHitMark()
        guard let highlightLength, highlightLength > 0,
              let start = offset(line: line, column: column),
              let emphasisManager = controller.textView?.emphasisManager else { return }
        let text = controller.text as NSString
        let range = NSRange(location: start, length: min(highlightLength, text.length - start))
        emphasisManager.addEmphases([Emphasis(range: range, style: .standard)], for: Self.hitEmphasisID)
    }

    private static let hitEmphasisID = "search.hit"

    private func clearHitMark() {
        controller?.textView?.emphasisManager?.removeEmphases(for: Self.hitEmphasisID)
    }

    /// 1-based line:column → UTF-16 offset in the buffer, nil when out of range.
    private func offset(line: Int, column: Int) -> Int? {
        guard let controller, line >= 1, column >= 1 else { return nil }
        let text = controller.text as NSString
        var index = 0
        var current = 1
        while current < line, index < text.length {
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            current += 1
        }
        guard current == line else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: min(index, text.length), length: 0))
        return min(index + column - 1, NSMaxRange(lineRange))
    }

    /// Write the buffer back to its file. A preview has nothing to write.
    func save() throws {
        guard let controller, let filePath, !isPreview else { return }
        try controller.text.write(toFile: filePath, atomically: true, encoding: .utf8)
        isDirty = false
        lspClient?.didSave(path: filePath)
    }

    // MARK: LSP (M2.5 — definition + diagnostics, nothing else)

    /// The caret, 1-based, for definition requests. Nil when no buffer.
    var cursorPosition: (line: Int, column: Int)? {
        guard let position = controller?.cursorPositions.first?.start,
              position.line > 0, position.column > 0 else { return nil }
        return (position.line, position.column)
    }

    /// What the server last published for this buffer (dev-only: lspProbe).
    private(set) var lastDiagnostics: [LSPDiagnostic] = []

    /// Diagnostics land as underlines: error red, warning peach, the rest
    /// muted — colors the panes already speak. No gutter icons, no popovers;
    /// the message itself waits for a later milestone.
    private func showDiagnostics(_ diagnostics: [LSPDiagnostic]) {
        lastDiagnostics = diagnostics
        guard let controller, let emphasisManager = controller.textView.emphasisManager else { return }
        emphasisManager.removeEmphases(for: Self.diagnosticsEmphasisID)
        guard !diagnostics.isEmpty else { return }

        // LSP ranges are 0-based line + UTF-16 column; map through the
        // buffer's line starts. Entries that outrun the live text (stale
        // publish racing an edit) are dropped, not clamped.
        let text = controller.text as NSString
        var lineStarts: [Int] = []
        var index = 0
        while index < text.length {
            lineStarts.append(index)
            index = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
        }
        if lineStarts.isEmpty { lineStarts = [0] }

        let emphases: [Emphasis] = diagnostics.compactMap { diagnostic in
            guard diagnostic.startLine < lineStarts.count, diagnostic.endLine < lineStarts.count else { return nil }
            let start = lineStarts[diagnostic.startLine] + diagnostic.startCharacter
            let end = lineStarts[diagnostic.endLine] + diagnostic.endCharacter
            guard start <= end, end <= text.length else { return nil }
            // A zero-length range draws nothing; give point diagnostics a
            // one-character underline so they exist.
            let range = NSRange(location: start, length: max(1, end - start))
            guard NSMaxRange(range) <= text.length else { return nil }
            let color: NSColor = switch diagnostic.severity {
            case .error: Theme.accentRed
            case .warning: Theme.accentPeach
            case .information, .hint: Theme.chromeMutedText
            }
            return Emphasis(range: range, style: .underline(color: color))
        }
        emphasisManager.addEmphases(emphases, for: Self.diagnosticsEmphasisID)
        updateDiagnosticStrip()
    }

    private func clearDiagnostics() {
        lastDiagnostics = []
        controller?.textView.emphasisManager?.removeEmphases(for: Self.diagnosticsEmphasisID)
        updateDiagnosticStrip()
    }

    @objc private func caretMoved() {
        enterPreviewIfDoubleClicked()
        updateDiagnosticStrip()
    }

    /// The message for the diagnostic under the caret, in a one-line strip
    /// floating over the bottom of the buffer (so the text never reflows as
    /// the caret moves). Under the caret means: on its line, the one whose
    /// range contains the column winning; errors before warnings.
    private func updateDiagnosticStrip() {
        guard !isPreview, !lastDiagnostics.isEmpty,
              let position = controller?.cursorPositions.first?.start, position.line > 0 else {
            diagnosticStrip.isHidden = true
            return
        }
        let line = position.line - 1
        let column = max(0, position.column - 1)
        let onLine = lastDiagnostics.filter { $0.startLine <= line && line <= $0.endLine }
        guard !onLine.isEmpty else { diagnosticStrip.isHidden = true; return }
        func contains(_ d: LSPDiagnostic) -> Bool {
            let afterStart = line > d.startLine || column >= d.startCharacter
            let beforeEnd = line < d.endLine || column <= d.endCharacter
            return afterStart && beforeEnd
        }
        let pick = onLine.min { a, b in
            if contains(a) != contains(b) { return contains(a) }
            return a.severity.rawValue < b.severity.rawValue
        }!
        diagnosticStrip.show(pick)
        diagnosticStrip.isHidden = false
    }

    private static let diagnosticsEmphasisID = "lsp.diagnostics"

    /// Dev-only (snapshot): the buffer's scroll geometry, for chasing
    /// horizontal-scroll complaints without a pointer.
    var debugGeometry: String {
        guard let controller else { return "no buffer" }
        guard let sv = controller.scrollView else { return "no scroll view" }
        var hits: [String] = []
        if let root = window?.contentView {
            // Who answers a click across the content host's width, at mid-height.
            let midY = contentHost.bounds.midY
            for step in 0...11 {
                let x = contentHost.bounds.minX + contentHost.bounds.width * CGFloat(step) / 11
                let point = contentHost.convert(NSPoint(x: min(x, contentHost.bounds.maxX - 1), y: midY), to: root)
                let hit = root.hitTest(point).map { String(describing: type(of: $0)) } ?? "nil"
                hits.append("\(Int(x)):\(hit)")
            }
        }
        func find(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)) == "MinimapView" { return view }
            for sub in view.subviews { if let hit = find(sub) { return hit } }
            return nil
        }
        let minimap = find(controller.view)
        let minimapLine = "minimap hidden=\(minimap?.isHidden ?? true) frame=\(minimap?.frame ?? .zero) "
            + "superHidden=\(minimap?.isHiddenOrHasHiddenAncestor ?? true)"
        var out = "preview=\(isPreview) lang=\(bufferLanguage?.id.rawValue ?? "-") lsp=\(bufferLSPClient != nil) wrap=\(controller.wrapLines) hScroller=\(sv.hasHorizontalScroller) mask=\(gutterMask.frame) "
        out += "content=\(sv.contentSize) doc=\(controller.textView.frame.size) "
        out += "docVisible=\(sv.documentVisibleRect) estWidth=\(controller.textView.layoutManager.estimatedWidth())\n"
        out += "  hits: " + hits.joined(separator: " ") + "\n  " + minimapLine
        out += "\n  strip hidden=\(diagnosticStrip.isHidden) '\(diagnosticStrip.debugText)'"
        if let root = window?.contentView {
            // The find panel's row: 14pt under the header, across the width.
            var top: [String] = []
            let y = contentHost.isFlipped
                ? contentHost.bounds.minY + EditorFileHeader.height + 14
                : contentHost.bounds.maxY - EditorFileHeader.height - 14
            for step in 0...11 {
                let x = contentHost.bounds.minX + contentHost.bounds.width * CGFloat(step) / 11
                let point = contentHost.convert(NSPoint(x: min(x, contentHost.bounds.maxX - 1), y: y), to: root)
                let hit = root.hitTest(point)
                let chain = sequence(first: hit, next: { $0?.superview }).prefix(3).compactMap { $0 }.map { String(describing: type(of: $0)) }
                top.append("\(Int(x)):\(chain.joined(separator: "<"))")
            }
            out += "\n  topHits: " + top.joined(separator: " ")
            let panels = controller.view.subviews.flatMap { [$0] + $0.subviews }.filter { String(describing: type(of: $0)).contains("FindPanel") }
            out += "\n  findPanel: " + panels.map { "\(type(of: $0)) frame=\($0.frame) hidden=\($0.isHidden)" }.joined(separator: "; ")
        }
        if let lang = bufferLanguage {
            let url = lang.queryURL
            let exists = url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            out += "\n  ts query=\(TreeSitterModel.shared.query(for: lang.id) != nil) url=\(url?.path ?? "-") exists=\(exists) tsLang=\(lang.language != nil)"
        }
        if let storage = controller.textView.textStorage {
            var colors: [String: Int] = [:]
            let probe = NSRange(location: 0, length: min(storage.length, 1500))
            storage.enumerateAttribute(.foregroundColor, in: probe) { value, range, _ in
                let key = (value as? NSColor).map { c in
                    let c = c.usingColorSpace(.sRGB) ?? c
                    return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
                } ?? "nil"
                colors[key, default: 0] += range.length
            }
            out += "\n  colors=\(colors.sorted { $0.value > $1.value }.map { "\($0.key):\($0.value)" }.joined(separator: " "))"
        }
        return out
    }

    // MARK: Configuration

    /// One Mocha (§2.9): syntax from `Theme.Editor`, background clear — the
    /// pane's `contentWash` paints base at fieldAlpha exactly once so the
    /// behind-window blur reads through — JetBrains Mono at terminal size. Minimap off — not this app's furniture. Bracket
    /// emphasis nil: the default flash is a motion the inventory doesn't own.
    /// A preview wraps to the pane; everything else is identical.
    /// The fine map (§2.9 continued, 2026-09-16): one Catppuccin colour per
    /// tree-sitter capture, catppuccin/nvim's assignments. Declaration
    /// keywords (`def`, `func`, `import`) stay mauve but go italic, so a
    /// definition reads apart from control flow without leaving the palette.
    private static let captureAttributes: [CaptureName: EditorTheme.Attribute] = {
        typealias A = EditorTheme.Attribute
        let e = Theme.Editor.self
        return [
            .keyword: A(color: e.keyword),
            .conditional: A(color: e.keyword),
            .repeat: A(color: e.keyword),
            .keywordReturn: A(color: e.keyword),
            .keywordFunction: A(color: e.keyword, italic: true),
            .include: A(color: e.keyword, italic: true),
            .function: A(color: e.function),
            .method: A(color: e.method),
            .functionBuiltin: A(color: e.builtinFunction),
            .constructor: A(color: e.constructor),
            .type: A(color: e.type),
            .typeBuiltin: A(color: e.type),
            .typeAlternate: A(color: e.type),
            .property: A(color: e.property),
            .parameter: A(color: e.parameter),
            .variable: A(color: e.text),
            .variableBuiltin: A(color: e.builtinVariable),
            .constant: A(color: e.constant),
            .constantBuiltin: A(color: e.constant),
            .boolean: A(color: e.constant),
            .number: A(color: e.number),
            .float: A(color: e.number),
            .string: A(color: e.string),
            .escape: A(color: e.escape),
            .operator: A(color: e.operatorSign),
            .punctuation: A(color: e.punctuation),
            .attribute: A(color: e.attribute),
            .namespace: A(color: e.namespace),
            .label: A(color: e.label),
            .tag: A(color: e.function),
            .comment: A(color: e.comment, italic: true),
            // Markup (markdown). No strikethrough trait in the editor's
            // Attribute, so ~~struck~~ is colour-only.
            .markupHeading1: A(color: e.heading1, bold: true),
            .markupHeading: A(color: e.heading, bold: true),
            .markupStrong: A(color: e.text, bold: true),
            .markupItalic: A(color: e.text, italic: true),
            .markupStrikethrough: A(color: e.strikethrough),
            .markupRaw: A(color: e.rawCode),
            .markupLink: A(color: e.link),
            .markupUrl: A(color: e.url, italic: true),
            .markupList: A(color: e.listMarker),
            .markupQuote: A(color: e.quote, italic: true),
        ]
    }()

    private static func configuration(wrap: Bool) -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: EditorTheme(
                    text: .init(color: Theme.Editor.text),
                    insertionPoint: Theme.Editor.cursor,
                    invisibles: .init(color: Theme.Editor.invisibles),
                    // Fully transparent: the library would paint this on the
                    // scroll view *and* the gutter, over the pane's own coat;
                    // the pane's `contentWash` is the one owner of the field
                    // colour. Base at alpha 0 rather than `.clear` — the
                    // library reads the colour's brightness for its light/dark
                    // choices, and `.clear` is generic gray, which throws.
                    background: Theme.Elevation.base.withAlphaComponent(0),
                    lineHighlight: Theme.Editor.lineHighlight,
                    selection: Theme.Editor.selection,
                    keywords: .init(color: Theme.Editor.keyword),
                    commands: .init(color: Theme.Editor.command),
                    types: .init(color: Theme.Editor.type),
                    attributes: .init(color: Theme.Editor.attribute),
                    variables: .init(color: Theme.Editor.function),
                    values: .init(color: Theme.Editor.constant),
                    numbers: .init(color: Theme.Editor.number),
                    strings: .init(color: Theme.Editor.string),
                    characters: .init(color: Theme.Editor.character),
                    comments: .init(color: Theme.Editor.comment, italic: true),
                    captures: captureAttributes
                ),
                font: Theme.Typography.mono(Theme.TypeScale.current),
                wrapLines: wrap,
                tabWidth: 4,
                bracketPairEmphasis: nil
            ),
            behavior: .init(indentOption: .spaces(count: 4)),
            layout: .init(),
            // No fold ribbon: folding isn't wired, and the ribbon is 11pt of
            // gutter for nothing.
            peripherals: .init(showGutter: true, showMinimap: false, showFoldingRibbon: false)
        )
    }
}

/// Minimal edit observer — `textViewDidChangeText` is the dirty-tracking hook.
private final class ChangeCoordinator: TextViewCoordinator {
    var onTextChange: (() -> Void)?
    func prepareCoordinator(controller: TextViewController) {}
    func textViewDidChangeText(controller: TextViewController) { onTextChange?() }
}


// MARK: - File header

/// The strip over the buffer: which file this is (path from the root, mono),
/// a dot while it has unsaved edits, and for markdown the Text / Preview
/// toggle. Mantle over the buffer's base — a step up, not a toolbar.
final class EditorFileHeader: NSView {
    static let height: CGFloat = 26
    var onModeChange: ((Bool) -> Void)?
    var onBack: (() -> Void)?
    var onForward: (() -> Void)?
    var isDirty = false { didSet { dot.isHidden = !isDirty } }
    private let back = HoverPadButton(frame: .zero)
    private let forward = HoverPadButton(frame: .zero)

    private let name = NSTextField(labelWithString: "")
    private var markdownNameLimit: NSLayoutConstraint?
    private var plainNameLimit: NSLayoutConstraint?
    private let dot = NSView()
    private let mode = NSSegmentedControl(labels: ["Text", "Preview"], trackingMode: .selectOne, target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor

        name.font = Theme.Typography.mono(Theme.Typography.small)
        name.textColor = Theme.chromeText
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        dot.wantsLayer = true
        dot.layer?.backgroundColor = Theme.chromeText.cgColor
        dot.layer?.cornerRadius = 3
        dot.isHidden = true
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        mode.setAccessibilityLabel("Markdown display")
        mode.setToolTip("Edit markdown source", forSegment: 0)
        mode.setToolTip("Preview rendered markdown", forSegment: 1)
        mode.controlSize = .small
        mode.font = Theme.Typography.ui(Theme.Typography.small)
        mode.segmentStyle = .roundRect
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.isHidden = true
        mode.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mode)

        // Back / forward through the file history (owner ask 2026-09-16):
        // the browser's `< >`, at the title area's right edge. Disabled
        // ends fade rather than vanish, so the pair never jumps.
        for (button, symbol, action) in [(back, "chevron.left", #selector(goBack)), (forward, "chevron.right", #selector(goForward))] {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            button.contentTintColor = Theme.chromeText
            button.toolTip = symbol == "chevron.left" ? "Back  ⌃⌘←" : "Forward  ⌃⌘→"
            button.setAccessibilityLabel(symbol == "chevron.left" ? "Back" : "Forward")
            button.target = self
            button.action = action
            button.isEnabled = false
            button.alphaValue = 0.3
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 7),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            forward.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            forward.centerYAnchor.constraint(equalTo: centerYAnchor),
            forward.widthAnchor.constraint(equalToConstant: 20),
            forward.heightAnchor.constraint(equalToConstant: 20),
            back.trailingAnchor.constraint(equalTo: forward.leadingAnchor, constant: -2),
            back.centerYAnchor.constraint(equalTo: centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 20),
            back.heightAnchor.constraint(equalToConstant: 20),
            mode.trailingAnchor.constraint(equalTo: back.leadingAnchor, constant: -10),
            mode.centerYAnchor.constraint(equalTo: centerYAnchor),

            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    func configure(name text: String, markdown: Bool, previewOn: Bool) {
        if markdownNameLimit == nil {
            markdownNameLimit = name.trailingAnchor.constraint(lessThanOrEqualTo: mode.leadingAnchor, constant: -20)
            plainNameLimit = name.trailingAnchor.constraint(lessThanOrEqualTo: back.leadingAnchor, constant: -20)
        }
        markdownNameLimit?.isActive = false
        plainNameLimit?.isActive = false
        (markdown ? markdownNameLimit : plainNameLimit)?.isActive = true
        name.toolTip = text
        name.stringValue = text
        mode.isHidden = !markdown
        mode.selectedSegment = previewOn ? 1 : 0
    }

    @objc private func modeChanged() {
        onModeChange?(mode.selectedSegment == 1)
    }

    func setHistory(back canBack: Bool, forward canForward: Bool) {
        back.isEnabled = canBack
        back.alphaValue = canBack ? HoverPadButton.restingAlpha : 0.3
        forward.isEnabled = canForward
        forward.alphaValue = canForward ? HoverPadButton.restingAlpha : 0.3
    }

    @objc private func goBack() { onBack?() }
    @objc private func goForward() { onForward?() }
}

/// One line over the bottom edge of the buffer: severity dot, message.
/// Mantle over the base like the file header, so it reads as chrome, not
/// text; disappears when the caret leaves the diagnostic.
final class DiagnosticStrip: NSView {
    static let height: CGFloat = 22
    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor

        let hairline = NSView()
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        label.font = Theme.Typography.ui(Theme.Typography.small)
        label.textColor = Theme.chromeText
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Self.height),
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    var debugText: String { label.stringValue }

    func show(_ diagnostic: LSPDiagnostic) {
        let color: NSColor = switch diagnostic.severity {
        case .error: Theme.accentRed
        case .warning: Theme.accentPeach
        case .information, .hint: Theme.chromeMutedText
        }
        dot.layer?.backgroundColor = color.cgColor
        // Servers send multi-line messages (notes, fix-its); the first line is the verdict.
        label.stringValue = diagnostic.message
            .split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? diagnostic.message
        toolTip = diagnostic.message
    }
}

// MARK: - ⌘-hover / ⌘-click (the library's jump model, fed by the LSP client)

extension EditorPane: JumpToDefinitionDelegate {
    /// Definitions for the symbol at `range`. Same-file targets carry a
    /// resolved range (the model selects it directly); cross-file targets
    /// carry a URL and line/column and come back through `openLink`.
    func queryLinks(forRange range: NSRange, textView controller: TextViewController) async -> [JumpToDefinitionLink]? {
        guard !isPreview, let filePath, let client = bufferLSPClient,
              let position = controller.resolveCursorPosition(CursorPosition(range: NSRange(location: range.location, length: 0))),
              position.start.line > 0, position.start.column > 0 else { return nil }
        let text = controller.text as NSString
        guard NSMaxRange(range) <= text.length else { return nil }
        let symbol = text.substring(with: range)
        let targets = await withCheckedContinuation { (continuation: CheckedContinuation<[(path: String, line: Int, column: Int)], Never>) in
            client.definition(path: filePath, line: position.start.line - 1, character: position.start.column - 1) {
                continuation.resume(returning: $0)
            }
        }
        return targets.compactMap { target in
            if target.path == filePath {
                guard let resolved = controller.resolveCursorPosition(CursorPosition(line: target.line, column: target.column)) else { return nil }
                return JumpToDefinitionLink(url: nil, targetRange: resolved, typeName: symbol, sourcePreview: "", documentation: nil)
            }
            return JumpToDefinitionLink(
                url: URL(fileURLWithPath: target.path),
                targetRange: CursorPosition(line: target.line, column: target.column),
                typeName: symbol, sourcePreview: "", documentation: nil
            )
        }
    }

    func openLink(link: JumpToDefinitionLink) {
        guard let url = link.url else { return }
        onNavigateRequest?(url.path, link.targetRange.start.line, link.targetRange.start.column)
    }
}

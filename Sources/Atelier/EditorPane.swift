import AppKit
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
    /// ⌘-click in the buffer: go to definition at the caret.
    var onGoToDefinition: (() -> Void)?
    /// Everything right of the tree: the empty-state line, then the buffer.
    private let contentHost = NSView()
    private var contentLeading: NSLayoutConstraint!
    private var explorerWidth: NSLayoutConstraint!
    /// Wide (browsing) or folded to the rail (a file is open for real).
    private var explorerExpanded = true
    /// The buffer is a click-preview: soft-wrapped, not yet the session's
    /// file — persistence and the language server ignore it. Editable all
    /// the same: the first keystroke enters the file for real (unwrap, fold
    /// the tree), exactly like double-click/↩.
    private(set) var isPreview = false
    /// Soft-wrap follows the preview in, and leaves on a gesture commit only.
    private var isWrapped = false
    /// What the session persists: the committed file only.
    var committedFilePath: String? { isPreview ? nil : filePath }

    /// Absolute path of the open file, nil when the well is empty.
    private(set) var filePath: String?
    /// Unsaved edits exist. Owner is told on change (future tab/gutter marks).
    private(set) var isDirty = false {
        didSet { if oldValue != isDirty { onDirtyChange?(isDirty) } }
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
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
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
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
        layoutExplorer()
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
            installGutterMask(controller)
            controller.textView?.onCommandClick = { [weak self] _ in self?.onGoToDefinition?() }
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
            ])
            self.controller = controller
        }
        filePath = path
        isDirty = false // the coordinator saw the programmatic setText; undo it
        emptyLabel.isHidden = true
        explorer.reveal(path: path)
        bufferLanguage = language
        watchFile(path)

        if !preview {
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

    /// Preview → real: same text, unwrapped, the server learns of it, the
    /// tree folds away. Reached by double-click/↩ in the tree, the search
    /// bar, or the first keystroke into a preview.
    private func commitPreview() {
        guard let controller, let filePath else { return }
        let wasPreview = isPreview
        isPreview = false
        isWrapped = false
        controller.configuration = Self.configuration(wrap: false)
        if wasPreview { announceOpen(path: filePath, text: controller.text) }
        setExplorerExpanded(false)
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
        if isPreview {
            // Typing into a preview is entering the file: unwrap, fold the
            // tree, tell the server — same as double-click/↩ (owner call).
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
    }

    private func clearDiagnostics() {
        controller?.textView.emphasisManager?.removeEmphases(for: Self.diagnosticsEmphasisID)
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
        return out
    }

    // MARK: Configuration

    /// One Mocha (§2.9): syntax from `Theme.Editor`, background `base` at
    /// fieldAlpha so the behind-window blur reads through, JetBrains Mono at
    /// terminal size. Minimap off — not this app's furniture. Bracket
    /// emphasis nil: the default flash is a motion the inventory doesn't own.
    /// A preview wraps to the pane; everything else is identical.
    private static func configuration(wrap: Bool) -> SourceEditorConfiguration {
        SourceEditorConfiguration(
            appearance: .init(
                theme: EditorTheme(
                    text: .init(color: Theme.Editor.text),
                    insertionPoint: Theme.Editor.cursor,
                    invisibles: .init(color: Theme.Editor.invisibles),
                    background: Theme.Elevation.base,
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
                    comments: .init(color: Theme.Editor.comment, italic: true)
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

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
    /// Everything right of the tree: the empty-state line, then the buffer.
    private let contentHost = NSView()
    private var contentLeading: NSLayoutConstraint!
    private var explorerWidth: NSLayoutConstraint!
    /// Wide (browsing) or folded to the rail (a file is open for real).
    private var explorerExpanded = true
    /// The buffer is a click-preview: soft-wrapped, read-only, not the
    /// session's file — persistence and the language server ignore it.
    private(set) var isPreview = false
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
        guard let lspRoot, isSwiftBuffer, !isPreview else { return nil }
        return LSPRegistry.client(for: lspRoot)
    }
    private var isSwiftBuffer = false
    private var lspChangeDebounce: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
        buildChrome()
        buildEmptyState()
        explorer.onOpen = { [weak self] url, commit in self?.onOpenRequest?(url, commit) }
        explorer.onToggle = { [weak self] in self?.toggleExplorer() }
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    /// ⌘+/⌘−/⌘0 — the buffer rides the same content scale as the terminals.
    @objc private func typeScaleChanged() {
        controller?.configuration = Self.configuration(preview: isPreview)
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
    /// `preview` (a tree click): soft-wrapped and read-only, tree stays wide,
    /// nothing told to the server or to persistence. Committing the same path
    /// afterwards just flips the configuration — the text doesn't reload.
    func open(path: String, preview: Bool = false) throws {
        // Clicking the file that's already here changes nothing — a committed
        // buffer must not fall back to a read-only preview of itself.
        if preview, filePath == path { return }
        if !preview, isPreview, filePath == path, let controller {
            // Preview → real: same text, editable, unwrapped, the server
            // learns of it, the tree folds away.
            isPreview = false
            controller.configuration = Self.configuration(preview: false)
            announceOpen(path: path, text: controller.text)
            setExplorerExpanded(false)
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

        if let controller {
            controller.configuration = Self.configuration(preview: preview)
            controller.language = language
            controller.text = text
        } else {
            let controller = TextViewController(
                string: text,
                language: language,
                configuration: Self.configuration(preview: preview),
                cursorPositions: [CursorPosition(line: 1, column: 1)],
                coordinators: [changeCoordinator]
            )
            changeCoordinator.onTextChange = { [weak self] in self?.bufferChanged() }
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(controller.view)
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
        isSwiftBuffer = language == .swift

        if !preview {
            announceOpen(path: path, text: text)
            setExplorerExpanded(false)
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
        guard lspClient != nil else { return }
        lspChangeDebounce?.invalidate()
        lspChangeDebounce = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self, let path = self.filePath, let text = self.controller?.text else { return }
            self.lspClient?.didChange(path: path, text: text)
            self.lspClient?.requestDiagnostics(path: path)
        }
    }

    /// Put the caret at `line:column` (1-indexed) and scroll it into view —
    /// how a search hit lands (M2.3).
    func reveal(line: Int, column: Int) {
        controller?.setCursorPositions([CursorPosition(line: line, column: column)], scrollToVisible: true)
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
        return "preview=\(isPreview) wrap=\(controller.wrapLines) hScroller=\(sv.hasHorizontalScroller) "
            + "content=\(sv.contentSize) doc=\(controller.textView.frame.size) "
            + "docVisible=\(sv.documentVisibleRect) estWidth=\(controller.textView.layoutManager.estimatedWidth())"
    }

    // MARK: Configuration

    /// One Mocha (§2.9): syntax from `Theme.Editor`, background `base` at
    /// fieldAlpha so the behind-window blur reads through, JetBrains Mono at
    /// terminal size. Minimap off — not this app's furniture. Bracket
    /// emphasis nil: the default flash is a motion the inventory doesn't own.
    /// A preview wraps to the pane and refuses edits — reading, not writing.
    private static func configuration(preview: Bool) -> SourceEditorConfiguration {
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
                wrapLines: preview,
                tabWidth: 4,
                bracketPairEmphasis: nil
            ),
            behavior: .init(isEditable: !preview, indentOption: .spaces(count: 4)),
            layout: .init(),
            peripherals: .init(showGutter: true, showMinimap: false)
        )
    }
}

/// Minimal edit observer — `textViewDidChangeText` is the dirty-tracking hook.
private final class ChangeCoordinator: TextViewCoordinator {
    var onTextChange: (() -> Void)?
    func prepareCoordinator(controller: TextViewController) {}
    func textViewDidChangeText(controller: TextViewController) { onTextChange?() }
}

import AppKit
import CodeEditSourceEditor
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
    var focusView: NSView { controller?.textView ?? self }
    override var acceptsFirstResponder: Bool { controller == nil }

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
        buildEmptyState()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    private func buildEmptyState() {
        // Two-voice (§1.4): the chord is mono, Atelier's sentence is ui.
        let line = NSMutableAttributedString()
        line.append(NSAttributedString(string: "⌘O", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body),
            .foregroundColor: Theme.chromeText,
        ]))
        line.append(NSAttributedString(string: " open a file", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeMutedText,
        ]))
        emptyLabel.attributedStringValue = line
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: Open / save

    /// Open `path` into the buffer, detecting its language. The first open
    /// builds the editor; later opens reuse it. Any unsaved edits in the
    /// previous file are the caller's problem to guard.
    func open(path: String) throws {
        let url = URL(fileURLWithPath: path)
        let text = try String(contentsOf: url, encoding: .utf8)
        let language = CodeLanguage.detectLanguageFrom(url: url)

        if let controller {
            controller.language = language
            controller.text = text
        } else {
            let controller = TextViewController(
                string: text,
                language: language,
                configuration: Self.configuration(),
                cursorPositions: [CursorPosition(line: 1, column: 1)],
                coordinators: [changeCoordinator]
            )
            changeCoordinator.onTextChange = { [weak self] in self?.isDirty = true }
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(controller.view)
            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: topAnchor),
                controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.controller = controller
        }
        filePath = path
        isDirty = false // the coordinator saw the programmatic setText; undo it
        emptyLabel.isHidden = true
    }

    /// Put the caret at `line:column` (1-indexed) and scroll it into view —
    /// how a search hit lands (M2.3).
    func reveal(line: Int, column: Int) {
        controller?.setCursorPositions([CursorPosition(line: line, column: column)], scrollToVisible: true)
    }

    /// Write the buffer back to its file.
    func save() throws {
        guard let controller, let filePath else { return }
        try controller.text.write(toFile: filePath, atomically: true, encoding: .utf8)
        isDirty = false
    }

    // MARK: Configuration

    /// One Mocha (§2.9): syntax from `Theme.Editor`, background `base` at
    /// fieldAlpha so the behind-window blur reads through, JetBrains Mono at
    /// terminal size. Minimap off — not this app's furniture. Bracket
    /// emphasis nil: the default flash is a motion the inventory doesn't own.
    private static func configuration() -> SourceEditorConfiguration {
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
                font: Theme.Typography.mono(Theme.Typography.body),
                wrapLines: false,
                tabWidth: 4,
                bracketPairEmphasis: nil
            ),
            behavior: .init(indentOption: .spaces(count: 4)),
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

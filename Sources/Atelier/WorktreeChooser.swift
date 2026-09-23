import AppKit

/// The worktree chooser (MILESTONE_1 §6, revised 2026-09-03/08/21): the small
/// modal the row's `⎇+` / `⇧⌥⌘T` raise. One caption, one dropdown, and a
/// labeled Return action. Since 2026-09-21 the `+` starts a session here
/// without asking, so this card is only ever raised to go *somewhere else*:
/// it opens naming a new worktree (`↩` creates and starts, `↓` drops into
/// the existing ones), and the main checkout is no longer one reflex away; the dropdown unfolds an inline list of the
/// repo's worktrees (each removable by its hover `×`, behind a confirmation)
/// and offers a new one, which turns the dropdown into a name field. Typing
/// on the picker jumps straight into naming. `×` top-left, `Esc`, and a
/// scrim click dismiss.
final class WorktreeChooserOverlay: NSView, NSTextFieldDelegate {
    var onStart: ((Worktree) -> Void)?
    var onCreate: ((String) -> Void)?
    var onRemove: ((Worktree) -> Void)?

    private let worktrees: [Worktree]
    private var selected: Worktree
    private let onDismissHandler: () -> Void

    private let cardHost = NSView()
    private let card = OverlayMaterialView()
    private let hint = NSTextField(labelWithString: "")
    private let caption = NSTextField(labelWithString: "")
    private let picker = ChooserKeyView()
    private let dropdown = DropdownButton()
    private let nameHost = NSView()
    private let nameField = CenteredTextField()
    private let list: WorktreeListView
    private var listHeight: NSLayoutConstraint?
    private var cardWidth: NSLayoutConstraint?
    private let returnKey = KeyActionButton(keyHint: "↩")

    private enum Mode { case pick, name }
    private var mode: Mode = .pick
    private var listOpen = false


    /// `initial` is the suggestion (the active session's worktree); `prefill`
    /// opens the chooser already naming a new worktree; `openList` unfolds the
    /// list at once — what the `⎇+` / `⇧⌥⌘T` door wants, since choosing is the
    /// whole reason it was raised.
    init(worktrees: [Worktree], initial: Worktree? = nil, prefill: String? = nil,
         openList: Bool = false, onDismiss: @escaping () -> Void) {
        self.worktrees = worktrees
        self.selected = initial ?? worktrees.first(where: { $0.isPrimary }) ?? worktrees[0]
        self.list = WorktreeListView(worktrees: worktrees)
        self.onDismissHandler = onDismiss
        super.init(frame: .zero)
        build()
        if let prefill {
            enterNameMode(seed: prefill)
        } else if openList {
            self.openListOnPresent = true
        }
    }

    /// Set at init, spent by `animateIn` — the list can only unfold once the
    /// card has a window and a size to grow into.
    private var openListOnPresent = false

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The view to focus once presented.
    var focusField: NSView { mode == .pick ? picker : nameField }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.scrim.cgColor

        cardHost.wantsLayer = true
        cardHost.shadow = Theme.Elevation.floatingShadow
        cardHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardHost)

        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = Theme.Elevation.radiusLarge
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cardHost.addSubview(card)

        let topHairline = NSView()
        topHairline.wantsLayer = true
        topHairline.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        topHairline.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(topHairline)

        // × — top-left, muted until hovered (the tab-close idiom).
        let close = HoverPadButton()
        close.bezelStyle = .regularSquare
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        close.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        close.contentTintColor = Theme.chromeMutedText
        close.alphaValue = HoverPadButton.restingAlpha
        close.target = self
        close.action = #selector(dismissTapped)
        close.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(close)

        // The caption is Atelier speaking — SF Pro, body, the chrome cap (§1.4).
        caption.font = Theme.Typography.ui(Theme.Typography.body, weight: .medium)
        caption.textColor = Theme.chromeText
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(caption)

        // The picker: an invisible key-handling host the dropdown sits in.
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onReturn = { [weak self] in self?.confirm() }
        picker.onEscape = { [weak self] in self?.escape() }
        picker.onDown = { [weak self] in self?.arrow(1) }
        picker.onUp = { [weak self] in self?.arrow(-1) }
        picker.onOpenMenu = { [weak self] in self?.toggleList() }
        picker.onTyped = { [weak self] text in self?.enterNameMode(seed: text) }
        card.addSubview(picker)

        dropdown.target = self
        dropdown.action = #selector(dropdownTapped)
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        picker.addSubview(dropdown)

        // The name field replaces the dropdown in place when naming a worktree.
        // A single-line field top-aligns its editor, so the fill lives on a
        // host and the field is centered inside it.
        nameHost.wantsLayer = true
        nameHost.layer?.backgroundColor = Theme.Elevation.surface0.cgColor
        nameHost.layer?.cornerRadius = Theme.Elevation.radiusMedium
        nameHost.isHidden = true
        nameHost.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(nameHost)
        // Left-aligned (owner call 2026-09-21): centred, the caret of an
        // empty field landed in the middle of the placeholder.
        let placeholderParagraph = NSMutableParagraphStyle()
        placeholderParagraph.alignment = .left
        nameField.placeholderAttributedString = NSAttributedString(string: "name a new worktree", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body),
            .foregroundColor: Theme.chromeMutedText,
            .paragraphStyle: placeholderParagraph,
        ])
        nameField.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        nameField.textColor = Theme.chromeText
        nameField.alignment = .left
        nameField.focusRingType = .none
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.cell?.usesSingleLineMode = true
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameHost.addSubview(nameField)

        // The inline list: unfolds beneath the dropdown; the card grows with it.
        list.translatesAutoresizingMaskIntoConstraints = false
        list.onPick = { [weak self] index in self?.pick(index) }
        list.onRemove = { [weak self] worktree in self?.onRemove?(worktree) }
        // Hover moves the highlight, in either mode — pointer and keyboard
        // drive the same one thing (owner call 2026-09-21). It is safe to
        // arm by hover now that typing puts the highlight out: `↩` belongs
        // to the field whenever the field has text, and to the lit row only
        // when it does not — and that row is always visibly lit.
        list.onHover = { [weak self] index in self?.list.select(index) }
        // Losing or regaining the "New…" row changes how tall the list wants
        // to be; the card follows while it is open.
        list.onHeightChange = { [weak self] in
            guard let self, self.listOpen else { return }
            self.listHeight?.constant = min(self.list.naturalHeight, self.listLimit)
            self.layoutSubtreeIfNeeded()
        }
        list.alphaValue = 0
        list.isHidden = true
        card.addSubview(list)

        returnKey.target = self
        returnKey.action = #selector(returnTapped)
        returnKey.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(returnKey)
        hint.font = Theme.Typography.ui(Theme.Typography.small)
        hint.textColor = Theme.chromeMutedText
        hint.lineBreakMode = .byTruncatingTail
        hint.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(hint)
        close.toolTip = "Dismiss (Esc)"
        nameField.setAccessibilityLabel("New worktree branch name")
        nameHost.layer?.borderWidth = 1
        nameHost.layer?.borderColor = Theme.chromeMutedText.withAlphaComponent(0.45).cgColor

        let height = list.heightAnchor.constraint(equalToConstant: 0)
        listHeight = height

        let width = cardHost.widthAnchor.constraint(equalToConstant: 352)
        cardWidth = width
        NSLayoutConstraint.activate([
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            // A little above centre. Measured 2026-09-21: a positive constant
            // here moves the card *down* (the old +40 sat it 40pt low, which
            // only became obvious once the list rode along and the card grew).
            cardHost.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            width,

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            close.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 24),
            close.heightAnchor.constraint(equalToConstant: 24),

            caption.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
            caption.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),

            picker.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 14),
            picker.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            picker.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -48),
            picker.heightAnchor.constraint(equalToConstant: 36),

            dropdown.topAnchor.constraint(equalTo: picker.topAnchor),
            dropdown.bottomAnchor.constraint(equalTo: picker.bottomAnchor),
            dropdown.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
            dropdown.trailingAnchor.constraint(equalTo: picker.trailingAnchor),

            nameHost.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            nameHost.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            nameHost.widthAnchor.constraint(equalTo: picker.widthAnchor),
            nameHost.heightAnchor.constraint(equalToConstant: 36),
            nameField.centerYAnchor.constraint(equalTo: nameHost.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameHost.leadingAnchor, constant: 16),
            nameField.trailingAnchor.constraint(equalTo: nameHost.trailingAnchor, constant: -12),
            nameField.heightAnchor.constraint(equalToConstant: 20),

            list.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: picker.trailingAnchor),
            height,

            returnKey.topAnchor.constraint(equalTo: list.bottomAnchor, constant: 14),
            returnKey.trailingAnchor.constraint(equalTo: picker.trailingAnchor),
            returnKey.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            hint.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: returnKey.leadingAnchor, constant: -12),
            hint.centerYAnchor.constraint(equalTo: returnKey.centerYAnchor),
        ])

        applyMode()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // Keep this a constant: a width equality to the host can make AppKit
        // resize the entire window to the card's fitting width.
        cardWidth?.constant = min(352, max(0, newSize.width - 32))
        if listOpen {
            listHeight?.constant = min(list.naturalHeight, listLimit)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.listOpen else { return }
                self.layoutSubtreeIfNeeded()
                self.list.revealSelection()
            }
        }
    }

    private var listLimit: CGFloat { max(64, min(260, bounds.height - 260)) }

    // MARK: Modes

    private func applyMode() {
        switch mode {
        case .pick:
            caption.stringValue = "Start a session in"
            if selected.isPrimary {
                dropdown.show("main checkout", mono: false, detail: selected.branch)
            } else {
                dropdown.show(selected.branch, mono: true)
            }
            dropdown.toolTip = selected.path
            list.markCurrent(path: selected.path)
            dropdown.isHidden = false
            nameHost.isHidden = true
        case .name:
            caption.stringValue = "Start a session in"
            list.markCurrent(path: selected.path)
            dropdown.isHidden = true
            nameHost.isHidden = false
        }
        updateAction()
    }

    private func enterNameMode(seed: String) {
        // Typing *is* the new-worktree action now, so the row that used to
        // start it would be a no-op sitting in the list.
        list.showsNewRow = false
        // The list stays open beneath the field (owner call 2026-09-21): one
        // card that both asks for a new name and shows what already exists.
        setListOpen(true)
        mode = .name
        nameField.stringValue = seed
        applyMode()
        window?.makeFirstResponder(nameField)
        // Caret at the end of the seed, not a select-all.
        if let editor = nameField.currentEditor() as? NSTextView {
            editor.alignment = .left
            editor.selectedRange = NSRange(location: (seed as NSString).length, length: 0)
        }
    }

    // MARK: The list

    private func toggleList() {
        setListOpen(!listOpen)
        window?.makeFirstResponder(picker)
    }

    private func setListOpen(_ open: Bool) {
        guard open != listOpen else { return }
        listOpen = open
        list.isHidden = !open
        updateAction()
        dropdown.isOpen = open
        if open {
            list.select(worktrees.firstIndex(where: { $0.path == selected.path }) ?? 0)
        }
        let target: CGFloat = open ? min(list.naturalHeight, listLimit) : 0
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animate ? 0.15 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            listHeight?.animator().constant = target
            list.animator().alphaValue = open ? 1 : 0
            self.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            guard let self, self.listOpen else { return }
            self.list.revealSelection(fromTop: true)
        }
    }

    private func arrow(_ delta: Int) {
        if !listOpen {
            setListOpen(true)
        } else {
            list.move(delta)
        }
    }

    /// `↩` / click on a row: a worktree, or the trailing "New worktree…".
    private func pick(_ index: Int) {
        // Pointing at a worktree *is* the answer — the card's question was
        // "where", and a click says it (owner report 2026-09-21: the old
        // two-step choose-then-start survived from when the dropdown was
        // the only way in, so the first click merely armed a row, and doing
        // that put the now-redundant "New worktree…" row back).
        if index < worktrees.count {
            onStart?(worktrees[index])
        } else {
            enterNameMode(seed: "")
        }
    }

    private func escape() {
        if listOpen { setListOpen(false) } else { dismiss() }
    }

    @objc private func dropdownTapped() { toggleList() }
    @objc private func returnTapped() { confirm() }
    @objc private func dismissTapped() { dismiss() }

    private func confirm() {
        switch mode {
        case .pick:
            if listOpen {
                pick(list.selection)
            } else {
                onStart?(selected)
            }
        case .name:
            let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty {
                // Nothing typed: the card is acting as the picker it also is.
                if list.selectionShown, list.selection < worktrees.count {
                    onStart?(worktrees[list.selection])
                } else {
                    NSSound.beep()
                }
                return
            }
            guard nameIssue(name) == nil else {
                NSSound.beep()
                return
            }
            if let existing = worktrees.first(where: { $0.branch == name }) {
                // Naming an existing worktree is choosing it.
                onStart?(existing)
            } else {
                onCreate?(name)
            }
        }
    }

    // Validate without spawning git on the typing path. Git remains authoritative
    // for repository-specific conflicts when the action is committed.
    private func nameIssue(_ name: String) -> String? {
        if name.isEmpty { return nil }
        let invalid = CharacterSet(charactersIn: " ~^:?*[\\").union(.controlCharacters)
        if name == "@" || name.hasPrefix("-") || name.hasSuffix(".") ||
            name.contains("..") || name.contains("@{") ||
            name.unicodeScalars.contains(where: { invalid.contains($0) }) ||
            name.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                $0.isEmpty || $0.hasPrefix(".") || $0.hasSuffix(".lock")
            }) {
            return "Use a valid branch name"
        }
        return nil
    }

    private func updateAction() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let issue = mode == .name ? nameIssue(name) : nil
        let existing = worktrees.contains { $0.branch == name }
        if mode == .name {
            // The field owns `↩` the moment there is something in it.
            if name.isEmpty { list.select(list.selection) } else { list.clearSelection() }
        }
        returnKey.actionTitle = mode == .pick ? (listOpen ? "Choose" : "Start session")
            : (name.isEmpty || existing ? "Start session" : "Create & start")
        returnKey.isEnabled = mode == .pick || issue == nil
        hint.stringValue = issue ?? (mode == .name
            ? (name.isEmpty ? "↑ ↓ pick · type to name a new one" : "↩ creates the worktree")
            : (listOpen ? "↑ ↓ to navigate" : "↓ to choose worktree"))
        hint.textColor = issue == nil ? Theme.chromeMutedText : Theme.accentPeach
        hint.toolTip = issue
    }

    func controlTextDidChange(_ obj: Notification) { updateAction() }

    func dismiss() { onDismissHandler() }

    // MARK: NSTextFieldDelegate (name mode)

    func controlTextDidBeginEditing(_ obj: Notification) {
        // The field editor takes over drawing; it must align the same way.
        (nameField.currentEditor() as? NSTextView)?.alignment = .left
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            confirm()
            return true
        case #selector(NSResponder.moveDown(_:)):
            list.move(1)
            updateAction()
            return true
        case #selector(NSResponder.moveUp(_:)):
            list.move(-1)
            updateAction()
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            // The field editor turns an unhandled Esc into `complete:` (the
            // autocomplete popup) — claim both. There is no half-state to
            // step back to any more, so Esc leaves the card.
            dismiss()
            return true
        default:
            return false
        }
    }

    // MARK: Presentation

    /// The same descent the summon card makes (§6), scaled to a card this size.
    func animateIn() {
        if openListOnPresent {
            openListOnPresent = false
            layoutSubtreeIfNeeded()
            setListOpen(true)
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        layoutSubtreeIfNeeded()
        let target = cardHost.frame
        cardHost.frame = target.offsetBy(dx: 0, dy: 8)
        cardHost.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            cardHost.animator().frame = target
            cardHost.animator().alphaValue = 1
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !cardHost.frame.contains(point) { dismiss() }
    }
}

// MARK: - Pieces

/// The keyboard host of the pick mode: `↩` starts (or picks, when the list is
/// open), `Esc` closes the list then dismisses, `↓`/`↑` open and walk the
/// list, `Space`/`Tab` toggle it, and any printable character starts naming a
/// new worktree with that character already typed.
private final class ChooserKeyView: NSView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onDown: (() -> Void)?
    var onUp: (() -> Void)?
    var onOpenMenu: (() -> Void)?
    var onTyped: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()      // return, keypad enter
        case 53: onEscape?()          // escape
        case 125: onDown?()           // ↓
        case 126: onUp?()             // ↑
        case 49, 48: onOpenMenu?()    // space, tab
        default:
            if let text = event.characters,
               !text.isEmpty,
               event.modifierFlags.intersection([.command, .control]).isEmpty,
               text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                onTyped?(text)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

/// The inline worktree list: one row per worktree (the primary tagged
/// "main checkout", the others removable by a hover `×`), then "New
/// worktree…". A single selection highlight; hover moves it, keys walk it.
private final class WorktreeListView: NSScrollView {
    static let rowHeight: CGFloat = 32
    private let content = NSView()
    var onPick: ((Int) -> Void)?
    var onRemove: ((Worktree) -> Void)?
    var onHover: ((Int) -> Void)?
    private(set) var selection = 0

    private let worktrees: [Worktree]
    private var rows: [ListRow] = []

    /// Whether the trailing "New worktree…" row is part of the list. Off
    /// while the name field is asking for one anyway.
    var showsNewRow = true {
        didSet {
            guard showsNewRow != oldValue else { return }
            rows.last?.isHidden = !showsNewRow
            select(min(selection, visibleRows - 1))
            needsLayout = true
            onHeightChange?()
        }
    }
    var onHeightChange: (() -> Void)?
    private var visibleRows: Int { showsNewRow ? rows.count : rows.count - 1 }

    var naturalHeight: CGFloat { Self.rowHeight * CGFloat(visibleRows) + 4 }

    init(worktrees: [Worktree]) {
        self.worktrees = worktrees
        super.init(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        documentView = content
        wantsLayer = true
        for (index, worktree) in worktrees.enumerated() {
            // A worktree *is* its branch — one per branch, the name is the
            // place. The repo's own checkout is the exception: it's a place
            // whose branch drifts, so it wears the place and trails the ref.
            let row = worktree.isPrimary
                ? ListRow(title: "main checkout", mono: false,
                          suffix: worktree.branch, suffixMono: true, removable: false)
                : ListRow(title: worktree.branch, mono: true,
                          suffix: nil, removable: true)
            row.onClick = { [weak self] in self?.onPick?(index) }
            row.toolTip = worktree.path
            row.onRemove = { [weak self] in self?.onRemove?(worktree) }
            row.onHover = { [weak self] in self?.onHover?(index) }
            rows.append(row)
            content.addSubview(row)
        }
        let new = ListRow(title: "New worktree…", mono: false, suffix: nil, removable: false)
        new.onClick = { [weak self] in self?.onPick?(worktrees.count) }
        new.onHover = { [weak self] in self?.onHover?(worktrees.count) }
        rows.append(new)
        content.addSubview(new)
        // Clip the fold: rows below the animated height stay hidden.
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        content.setFrameSize(NSSize(width: contentSize.width, height: naturalHeight))
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(
                x: 0,
                y: naturalHeight - 2 - CGFloat(index + 1) * Self.rowHeight,
                width: content.bounds.width,
                height: Self.rowHeight - 2
            )
            // A hairline over the "New…" row separates it from the worktrees.
            row.showsTopRule = index == worktrees.count
        }
    }

    private(set) var selectionShown = true

    func select(_ index: Int) {
        selection = max(0, min(index, visibleRows - 1))
        selectionShown = true
        for (i, row) in rows.enumerated() { row.isSelected = i == selection }
    }

    /// Drop the highlight without forgetting where it was: while the name
    /// field has text, `↩` belongs to the field, so no row may look armed.
    func clearSelection() {
        guard selectionShown else { return }
        selectionShown = false
        for row in rows { row.isSelected = false }
    }

    func markCurrent(path: String) {
        for (index, row) in rows.enumerated() {
            row.isCurrent = index < worktrees.count && worktrees[index].path == path
        }
    }

    func revealSelection(fromTop: Bool = false) {
        layoutSubtreeIfNeeded()
        let row = rows[selection].frame.insetBy(dx: 0, dy: -2)
        var visible = contentView.bounds
        if fromTop { visible.origin.y = naturalHeight - visible.height }
        if row.minY < visible.minY { visible.origin.y = row.minY }
        if row.maxY > visible.maxY { visible.origin.y = row.maxY - visible.height }
        visible.origin.y = max(0, min(visible.origin.y, naturalHeight - visible.height))
        contentView.scroll(to: visible.origin)
        reflectScrolledClipView(contentView)
    }

    func move(_ delta: Int) {
        // Coming back from a cleared highlight, the first arrow re-lights
        // where it was rather than stepping past it.
        guard selectionShown else { select(selection); revealSelection(); return }
        select((selection + delta + visibleRows) % visibleRows)
        revealSelection()
    }
}

/// One list row: title (mono for branches, SF Pro for the action), optional
/// muted suffix, optional hover `×`. Selected → surface1 fill.
private final class ListRow: NSView {
    var onClick: (() -> Void)?
    var onRemove: (() -> Void)?
    var onHover: (() -> Void)?
    var showsTopRule = false { didSet { rule.isHidden = !showsTopRule } }
    var isSelected = false {
        didSet { layer?.backgroundColor = (isSelected ? Theme.Elevation.surface1 : .clear).cgColor }
    }

    private let label = NSTextField(labelWithString: "")
    private let check = NSImageView()
    var isCurrent = false { didSet { check.isHidden = !isCurrent } }
    private let suffixLabel = NSTextField(labelWithString: "")
    private let remove = HoverPadButton()
    private let rule = NSView()
    private var tracking: NSTrackingArea?

    init(title: String, mono: Bool, suffix: String?, suffixMono: Bool = false, removable: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusMedium

        label.stringValue = title
        label.font = mono
            ? Theme.Typography.mono(Theme.Typography.body)
            : Theme.Typography.ui(Theme.Typography.body)
        label.textColor = Theme.chromeText
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        suffixLabel.stringValue = suffix ?? ""
        suffixLabel.font = suffixMono
            ? Theme.Typography.mono(Theme.Typography.small)
            : Theme.Typography.ui(Theme.Typography.small)
        suffixLabel.textColor = Theme.chromeMutedText
        suffixLabel.isHidden = suffix == nil
        suffixLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        suffixLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(suffixLabel)

        remove.bezelStyle = .regularSquare
        remove.isBordered = false
        remove.imagePosition = .imageOnly
        remove.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove worktree")
        remove.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        // Full chrome ink, not the muted cap: at 9pt over a raised row the
        // muted tone was barely there (owner call 2026-09-21).
        remove.contentTintColor = Theme.chromeText
        remove.alphaValue = 0 // revealed on row hover
        remove.toolTip = "Remove worktree…"
        remove.setAccessibilityLabel("Remove \(title)")
        remove.isHidden = !removable
        remove.target = self
        remove.action = #selector(removeTapped)
        remove.translatesAutoresizingMaskIntoConstraints = false
        addSubview(remove)

        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Current worktree")
        check.symbolConfiguration = .init(pointSize: 10, weight: .semibold)
        check.contentTintColor = Theme.chromeText
        check.isHidden = true
        check.translatesAutoresizingMaskIntoConstraints = false
        addSubview(check)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title + (suffix.map { ", " + $0 } ?? ""))

        rule.wantsLayer = true
        rule.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        rule.isHidden = true
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        NSLayoutConstraint.activate([
            check.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            check.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            suffixLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            suffixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            suffixLabel.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -8),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            remove.centerYAnchor.constraint(equalTo: centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 24),
            remove.heightAnchor.constraint(equalToConstant: 24),
            rule.topAnchor.constraint(equalTo: topAnchor, constant: -1),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            rule.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?()
        if !remove.isHidden { remove.alphaValue = 1 }
    }

    override func mouseExited(with event: NSEvent) {
        remove.alphaValue = 0
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool { onClick?(); return true }

    @objc private func removeTapped() { onRemove?() }
}

/// The dropdown: the chosen worktree centered on a raised surface0 fill, a
/// chevron at the trailing edge that turns when the list is open. A worktree
/// shows its branch in mono; the repo's own checkout shows "main checkout"
/// with the branch it currently sits on trailing in dim mono.
private final class DropdownButton: OverlayActionButton {
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    var isOpen = false {
        didSet {
            chevron.image = NSImage(systemSymbolName: isOpen ? "chevron.up" : "chevron.down", accessibilityDescription: nil)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.surface0.cgColor
        layer?.cornerRadius = Theme.Elevation.radiusMedium

        label.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        label.textColor = Theme.chromeText
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = Theme.chromeMutedText
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            // Centered on the control, with the chevron's slot mirrored on the
            // left so the text sits truly centered.
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var title: String {
        get { label.stringValue }
        set { show(newValue, mono: true) }
    }

    /// `text` in the voice its kind calls for, `detail` trailing in dim mono.
    func show(_ text: String, mono: Bool, detail: String? = nil) {
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineBreakMode = .byTruncatingMiddle
        let value = NSMutableAttributedString(string: text, attributes: [
            .font: mono
                ? Theme.Typography.mono(Theme.Typography.body, weight: .medium)
                : Theme.Typography.ui(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeText,
            .paragraphStyle: centered,
        ])
        if let detail {
            value.append(NSAttributedString(string: "  " + detail, attributes: [
                .font: Theme.Typography.mono(Theme.Typography.small),
                .foregroundColor: Theme.chromeMutedText,
                .paragraphStyle: centered,
            ]))
        }
        label.attributedStringValue = value
        setAccessibilityLabel("Worktree: " + text + (detail.map { ", " + $0 } ?? ""))
    }

    override func draw(_ dirtyRect: NSRect) {} // the layer is the whole look
}

/// A text field whose field editor aligns as the field does.
private final class CenteredTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.alignment = .left
        return ok
    }
}

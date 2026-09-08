import AppKit

/// The worktree chooser (MILESTONE_1 §6, revised 2026-09-03/08): the small
/// modal the `+` / `⌥⌘T` raise before a session starts. One caption, one
/// dropdown, `↩`. The suggestion is the worktree you're already in, so the
/// fast path is *plus, enter*; the dropdown unfolds an inline list of the
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
    private let card = NSVisualEffectView()
    private let caption = NSTextField(labelWithString: "")
    private let picker = ChooserKeyView()
    private let dropdown = DropdownButton()
    private let nameHost = NSView()
    private let nameField = CenteredTextField()
    private let list: WorktreeListView
    private var listHeight: NSLayoutConstraint?
    private let returnKey = ReturnKeyButton()

    private enum Mode { case pick, name }
    private var mode: Mode = .pick
    private var listOpen = false

    static let controlWidth: CGFloat = 264

    /// `initial` is the suggestion (the active session's worktree); `prefill`
    /// opens the chooser already naming a new worktree.
    init(worktrees: [Worktree], initial: Worktree? = nil, prefill: String? = nil, onDismiss: @escaping () -> Void) {
        self.worktrees = worktrees
        self.selected = initial ?? worktrees.first(where: { $0.isPrimary }) ?? worktrees[0]
        self.list = WorktreeListView(worktrees: worktrees)
        self.onDismissHandler = onDismiss
        super.init(frame: .zero)
        build()
        if let prefill {
            enterNameMode(seed: prefill)
        }
    }

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
        let close = HoverFadeIconButton()
        close.bezelStyle = .regularSquare
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        close.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        close.contentTintColor = Theme.chromeMutedText
        close.alphaValue = HoverFadeIconButton.restingAlpha
        close.target = self
        close.action = #selector(dismissTapped)
        close.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(close)

        // The caption is Atelier speaking — SF Pro, body, the chrome cap (§1.4).
        caption.font = Theme.Typography.ui(Theme.Typography.body)
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
        nameField.placeholderString = "branch name"
        nameField.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        nameField.textColor = Theme.chromeText
        nameField.alignment = .center
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
        list.onHover = { [weak self] index in self?.list.select(index) }
        list.alphaValue = 0
        card.addSubview(list)

        returnKey.target = self
        returnKey.action = #selector(returnTapped)
        returnKey.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(returnKey)

        let height = list.heightAnchor.constraint(equalToConstant: 0)
        listHeight = height

        NSLayoutConstraint.activate([
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardHost.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40), // sits a little above center
            cardHost.widthAnchor.constraint(equalToConstant: 340),

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            close.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),

            caption.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 40),
            caption.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -40),

            picker.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 14),
            picker.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            picker.widthAnchor.constraint(equalToConstant: Self.controlWidth),
            picker.heightAnchor.constraint(equalToConstant: 30),

            dropdown.topAnchor.constraint(equalTo: picker.topAnchor),
            dropdown.bottomAnchor.constraint(equalTo: picker.bottomAnchor),
            dropdown.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
            dropdown.trailingAnchor.constraint(equalTo: picker.trailingAnchor),

            nameHost.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            nameHost.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            nameHost.widthAnchor.constraint(equalToConstant: Self.controlWidth),
            nameHost.heightAnchor.constraint(equalToConstant: 30),
            nameField.centerYAnchor.constraint(equalTo: nameHost.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameHost.leadingAnchor, constant: 12),
            nameField.trailingAnchor.constraint(equalTo: nameHost.trailingAnchor, constant: -12),
            nameField.heightAnchor.constraint(equalToConstant: 20),

            list.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: picker.trailingAnchor),
            height,

            returnKey.topAnchor.constraint(equalTo: list.bottomAnchor, constant: 14),
            returnKey.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            returnKey.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        applyMode()
    }

    // MARK: Modes

    private func applyMode() {
        switch mode {
        case .pick:
            caption.stringValue = "Start a session in"
            dropdown.title = selected.branch
            dropdown.isHidden = false
            nameHost.isHidden = true
        case .name:
            caption.stringValue = "Name the new worktree"
            dropdown.isHidden = true
            nameHost.isHidden = false
        }
    }

    private func enterNameMode(seed: String) {
        setListOpen(false)
        mode = .name
        nameField.stringValue = seed
        applyMode()
        window?.makeFirstResponder(nameField)
        // Caret at the end of the seed, not a select-all.
        if let editor = nameField.currentEditor() as? NSTextView {
            editor.alignment = .center
            editor.selectedRange = NSRange(location: (seed as NSString).length, length: 0)
        }
    }

    private func leaveNameMode() {
        mode = .pick
        applyMode()
        window?.makeFirstResponder(picker)
    }

    // MARK: The list

    private func toggleList() { setListOpen(!listOpen) }

    private func setListOpen(_ open: Bool) {
        guard open != listOpen else { return }
        listOpen = open
        dropdown.isOpen = open
        if open {
            list.select(worktrees.firstIndex(where: { $0.path == selected.path }) ?? 0)
        }
        let target: CGFloat = open ? list.naturalHeight : 0
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animate ? 0.15 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            listHeight?.animator().constant = target
            list.animator().alphaValue = open ? 1 : 0
            self.layoutSubtreeIfNeeded()
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
        if index < worktrees.count {
            selected = worktrees[index]
            setListOpen(false)
            applyMode()
            window?.makeFirstResponder(picker)
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
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
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

    func dismiss() { onDismissHandler() }

    // MARK: NSTextFieldDelegate (name mode)

    func controlTextDidBeginEditing(_ obj: Notification) {
        // The field editor takes over drawing; it must center too.
        (nameField.currentEditor() as? NSTextView)?.alignment = .center
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            confirm()
            return true
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)):
            // The field editor turns an unhandled Esc into `complete:` (the
            // autocomplete popup) — claim both so Esc always steps back.
            leaveNameMode()
            return true
        default:
            return false
        }
    }

    // MARK: Presentation

    /// The same descent the summon card makes (§6), scaled to a card this size.
    func animateIn() {
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
private final class WorktreeListView: NSView {
    static let rowHeight: CGFloat = 28
    var onPick: ((Int) -> Void)?
    var onRemove: ((Worktree) -> Void)?
    var onHover: ((Int) -> Void)?
    private(set) var selection = 0

    private let worktrees: [Worktree]
    private var rows: [ListRow] = []

    var naturalHeight: CGFloat { Self.rowHeight * CGFloat(worktrees.count + 1) + 4 }

    init(worktrees: [Worktree]) {
        self.worktrees = worktrees
        super.init(frame: .zero)
        wantsLayer = true
        for (index, worktree) in worktrees.enumerated() {
            let row = ListRow(
                title: worktree.branch,
                mono: true,
                suffix: worktree.isPrimary ? "main checkout" : nil,
                removable: !worktree.isPrimary
            )
            row.onClick = { [weak self] in self?.onPick?(index) }
            row.onRemove = { [weak self] in self?.onRemove?(worktree) }
            row.onHover = { [weak self] in self?.onHover?(index) }
            rows.append(row)
            addSubview(row)
        }
        let new = ListRow(title: "New worktree…", mono: false, suffix: nil, removable: false)
        new.onClick = { [weak self] in self?.onPick?(worktrees.count) }
        new.onHover = { [weak self] in self?.onHover?(worktrees.count) }
        rows.append(new)
        addSubview(new)
        // Clip the fold: rows below the animated height stay hidden.
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        for (index, row) in rows.enumerated() {
            row.frame = CGRect(
                x: 0,
                y: naturalHeight - 2 - CGFloat(index + 1) * Self.rowHeight,
                width: bounds.width,
                height: Self.rowHeight
            )
            // A hairline over the "New…" row separates it from the worktrees.
            row.showsTopRule = index == worktrees.count
        }
    }

    func select(_ index: Int) {
        selection = max(0, min(index, rows.count - 1))
        for (i, row) in rows.enumerated() { row.isSelected = i == selection }
    }

    func move(_ delta: Int) {
        select((selection + delta + rows.count) % rows.count)
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
    private let suffixLabel = NSTextField(labelWithString: "")
    private let remove = HoverFadeIconButton()
    private let rule = NSView()
    private var tracking: NSTrackingArea?

    init(title: String, mono: Bool, suffix: String?, removable: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusMedium

        label.stringValue = title
        label.font = mono
            ? Theme.Typography.mono(Theme.Typography.body)
            : Theme.Typography.ui(Theme.Typography.body)
        label.textColor = Theme.chromeText
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        suffixLabel.stringValue = suffix ?? ""
        suffixLabel.font = Theme.Typography.ui(Theme.Typography.small)
        suffixLabel.textColor = Theme.chromeMutedText
        suffixLabel.isHidden = suffix == nil
        suffixLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(suffixLabel)

        remove.bezelStyle = .regularSquare
        remove.isBordered = false
        remove.imagePosition = .imageOnly
        remove.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove worktree")
        remove.symbolConfiguration = .init(pointSize: 9, weight: .medium)
        remove.contentTintColor = Theme.chromeMutedText
        remove.alphaValue = 0 // revealed on row hover
        remove.isHidden = !removable
        remove.target = self
        remove.action = #selector(removeTapped)
        remove.translatesAutoresizingMaskIntoConstraints = false
        addSubview(remove)

        rule.wantsLayer = true
        rule.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        rule.isHidden = true
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            suffixLabel.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            suffixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            suffixLabel.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -8),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            remove.centerYAnchor.constraint(equalTo: centerYAnchor),
            remove.widthAnchor.constraint(equalToConstant: 16),
            remove.heightAnchor.constraint(equalToConstant: 16),
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
        if !remove.isHidden { remove.alphaValue = HoverFadeIconButton.restingAlpha }
    }

    override func mouseExited(with event: NSEvent) {
        remove.alphaValue = 0
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    @objc private func removeTapped() { onRemove?() }
}

/// The dropdown: the branch centered in mono on a raised surface0 fill, a
/// chevron at the trailing edge that turns when the list is open.
private final class DropdownButton: NSButton {
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
        set { label.stringValue = newValue }
    }

    override func draw(_ dirtyRect: NSRect) {} // the layer is the whole look
}

/// A text field whose field editor centers as the field does.
private final class CenteredTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        (currentEditor() as? NSTextView)?.alignment = .center
        return ok
    }
}

/// The confirm affordance: a `↩` keycap you can click — it says "just hit
/// Enter" by being the key itself (Theme.Typography.Keycap).
private final class ReturnKeyButton: NSButton {
    private let label = NSTextField(labelWithString: "↩")
    private var tracking: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.backgroundColor = Theme.Typography.Keycap.fill.cgColor
        layer?.cornerRadius = Theme.Typography.Keycap.radius

        label.font = Theme.Typography.mono(Theme.Typography.body)
        label.textColor = Theme.chromeText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let topEdge = NSView()
        topEdge.wantsLayer = true
        topEdge.layer?.backgroundColor = Theme.Typography.Keycap.topEdge.cgColor
        topEdge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topEdge)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 24),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            topEdge.topAnchor.constraint(equalTo: topAnchor),
            topEdge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Typography.Keycap.radius),
            topEdge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Typography.Keycap.radius),
            topEdge.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {}

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Theme.Elevation.surface1.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = Theme.Typography.Keycap.fill.cgColor
    }
}

/// A muted icon button that comes to full alpha under the pointer.
private final class HoverFadeIconButton: NSButton {
    static let restingAlpha: CGFloat = 0.55
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { alphaValue = 1.0 }
    override func mouseExited(with event: NSEvent) { alphaValue = Self.restingAlpha }
}

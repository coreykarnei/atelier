import AppKit

/// The worktree chooser (MILESTONE_1 §6, revised 2026-09-03): the small modal
/// the `+` / `⌥⌘T` raises before a session starts. One caption, one dropdown,
/// `↩`. The default is the main checkout, so the fast path is *plus, enter*;
/// the dropdown lists the repo's other worktrees and offers a new one, which
/// turns the dropdown into a name field. Typing on the picker jumps straight
/// into naming (the first keystroke lands somewhere meaningful). `×` top-left
/// and `Esc` dismiss; a click on the scrim does too.
final class WorktreeChooserOverlay: NSView, NSTextFieldDelegate {
    var onStart: ((Worktree) -> Void)?
    var onCreate: ((String) -> Void)?

    private let worktrees: [Worktree]
    private var selected: Worktree
    private let onDismissHandler: () -> Void

    private let cardHost = NSView()
    private let card = NSVisualEffectView()
    private let caption = NSTextField(labelWithString: "")
    private let picker = ChooserKeyView()
    private let dropdown = DropdownButton()
    private let nameField = NSTextField()
    private let returnKey = ReturnKeyButton()

    private enum Mode { case pick, name }
    private var mode: Mode = .pick

    /// `prefill` opens the chooser already naming a new worktree (the
    /// orphan-restore notice aims it at recreating a branch).
    init(worktrees: [Worktree], prefill: String? = nil, onDismiss: @escaping () -> Void) {
        self.worktrees = worktrees
        self.selected = worktrees.first(where: { $0.isPrimary }) ?? worktrees[0]
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

        // The caption is Atelier speaking — SF Pro, small, muted (§1.4).
        caption.font = Theme.Typography.ui(Theme.Typography.small)
        caption.textColor = Theme.chromeMutedText
        caption.alignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(caption)

        // The picker: an invisible key-handling host the dropdown sits in.
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.onReturn = { [weak self] in self?.confirm() }
        picker.onEscape = { [weak self] in self?.dismiss() }
        picker.onOpenMenu = { [weak self] in self?.showMenu() }
        picker.onTyped = { [weak self] text in self?.enterNameMode(seed: text) }
        card.addSubview(picker)

        dropdown.target = self
        dropdown.action = #selector(dropdownTapped)
        dropdown.translatesAutoresizingMaskIntoConstraints = false
        picker.addSubview(dropdown)

        // The name field replaces the dropdown in place when naming a worktree.
        nameField.placeholderString = "branch name"
        nameField.font = Theme.Typography.mono(Theme.Typography.body)
        nameField.textColor = Theme.chromeText
        nameField.alignment = .center
        nameField.focusRingType = .none
        nameField.isBordered = false
        nameField.drawsBackground = true
        nameField.backgroundColor = Theme.Elevation.surface0
        nameField.wantsLayer = true
        nameField.layer?.cornerRadius = Theme.Elevation.radiusMedium
        nameField.layer?.masksToBounds = true
        nameField.delegate = self
        nameField.isHidden = true
        nameField.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(nameField)

        returnKey.target = self
        returnKey.action = #selector(returnTapped)
        returnKey.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(returnKey)

        NSLayoutConstraint.activate([
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardHost.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40), // sits a little above center
            cardHost.widthAnchor.constraint(equalToConstant: 320),

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            close.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            close.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),

            caption.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            caption.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 36),
            caption.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -36),

            picker.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 10),
            picker.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            picker.heightAnchor.constraint(equalToConstant: 28),
            picker.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            picker.widthAnchor.constraint(lessThanOrEqualToConstant: 248),

            dropdown.topAnchor.constraint(equalTo: picker.topAnchor),
            dropdown.bottomAnchor.constraint(equalTo: picker.bottomAnchor),
            dropdown.leadingAnchor.constraint(equalTo: picker.leadingAnchor),
            dropdown.trailingAnchor.constraint(equalTo: picker.trailingAnchor),

            nameField.centerYAnchor.constraint(equalTo: picker.centerYAnchor),
            nameField.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 248),
            nameField.heightAnchor.constraint(equalToConstant: 28),

            returnKey.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 14),
            returnKey.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            returnKey.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])

        applyMode()
    }

    // MARK: Modes

    private func applyMode() {
        switch mode {
        case .pick:
            caption.stringValue = "Starting a session in worktree"
            dropdown.title = selected.branch
            dropdown.isHidden = false
            nameField.isHidden = true
        case .name:
            caption.stringValue = "Naming a new worktree"
            dropdown.isHidden = true
            nameField.isHidden = false
        }
    }

    private func enterNameMode(seed: String) {
        mode = .name
        nameField.stringValue = seed
        applyMode()
        window?.makeFirstResponder(nameField)
        // Caret at the end of the seed, not a select-all.
        if let editor = nameField.currentEditor() {
            editor.selectedRange = NSRange(location: (seed as NSString).length, length: 0)
        }
    }

    private func leaveNameMode() {
        mode = .pick
        applyMode()
        window?.makeFirstResponder(picker)
    }

    // MARK: The dropdown

    private func showMenu() {
        let menu = NSMenu()
        menu.font = Theme.Typography.mono(Theme.Typography.body)
        for worktree in worktrees {
            let item = NSMenuItem(title: worktree.branch, action: #selector(worktreePicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = worktree.path
            item.state = worktree.path == selected.path ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let new = NSMenuItem(title: "New worktree…", action: #selector(newWorktreePicked), keyEquivalent: "")
        new.target = self
        new.attributedTitle = NSAttributedString(string: "New worktree…", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body),
        ])
        menu.addItem(new)

        // Anchor the menu so the selected row lands over the dropdown label.
        let current = menu.items.first { ($0.representedObject as? String) == selected.path }
        menu.popUp(positioning: current, at: NSPoint(x: 0, y: dropdown.bounds.height), in: dropdown)
    }

    @objc private func worktreePicked(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              let worktree = worktrees.first(where: { $0.path == path }) else { return }
        selected = worktree
        applyMode()
        window?.makeFirstResponder(picker)
    }

    @objc private func newWorktreePicked() { enterNameMode(seed: "") }

    @objc private func dropdownTapped() { showMenu() }
    @objc private func returnTapped() { confirm() }
    @objc private func dismissTapped() { dismiss() }

    private func confirm() {
        switch mode {
        case .pick:
            onStart?(selected)
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

/// The keyboard host of the pick mode: `↩` starts, `Esc` dismisses, `↓` /
/// `Space` open the dropdown, and any printable character starts naming a
/// new worktree with that character already typed.
private final class ChooserKeyView: NSView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?
    var onOpenMenu: (() -> Void)?
    var onTyped: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onReturn?()      // return, keypad enter
        case 53: onEscape?()          // escape
        case 125, 49: onOpenMenu?()   // down arrow, space
        case 48: onOpenMenu?()        // tab — the dropdown is the only control
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

/// The dropdown: the branch in mono on a raised surface0 fill with a chevron —
/// a menu trigger that reads as one (§Phase-0: raised controls are opaque).
private final class DropdownButton: NSButton {
    private let label = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        self.title = ""
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.surface0.cgColor
        layer?.cornerRadius = Theme.Elevation.radiusMedium

        label.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        label.textColor = Theme.chromeText
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        chevron.contentTintColor = Theme.chromeMutedText
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
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

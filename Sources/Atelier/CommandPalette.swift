import AppKit

/// One palette entry. `key` is the display chord (the palette teaches the keymap).
struct PaletteCommand {
    let id: String
    let title: String
    let key: String?
    let action: () -> Void
}

/// Recently run command ids — they float to the top of the palette.
private enum RecentCommands {
    private static let key = "palette.recents"

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func bump(_ id: String) {
        var list = all().filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(10)), forKey: key)
    }
}

/// The command palette (MILESTONE_1 §8): a centered overlay descending from the
/// titlebar — the discoverable backstop for every action. The command set is
/// curated and fixed; the dedicated fast paths (⌘P, ⌘⇧F, the fan) stay separate.
/// The field + list interaction is the shared summon idiom (Summon.swift); this
/// file owns only the floating chrome and the command semantics.
final class CommandPalette: NSView {
    private let commands: [PaletteCommand]
    private let onDismiss: () -> Void

    /// Carries the floating shadow; the card itself masks to its rounded
    /// corners, which would clip a shadow set on its own layer.
    private let cardHost = NSView()
    private let card = NSVisualEffectView()
    private let summon: SummonList
    private var listHeight: NSLayoutConstraint?

    init(commands: [PaletteCommand], onDismiss: @escaping () -> Void) {
        let recents = RecentCommands.all()
        // Recents first (most recent leading), then declaration order.
        self.commands = commands.sorted { a, b in
            let ra = recents.firstIndex(of: a.id) ?? Int.max
            let rb = recents.firstIndex(of: b.id) ?? Int.max
            return ra != rb ? ra < rb
                : commands.firstIndex(where: { $0.id == a.id })! < commands.firstIndex(where: { $0.id == b.id })!
        }
        self.onDismiss = onDismiss
        self.summon = SummonList(style: .init(
            placeholder: "Type a command…",
            fieldFont: Theme.Typography.ui(Theme.Typography.large),
            placeholderFont: nil,
            rowHeight: 28,
            rowInset: 14,
            noMatchText: "No matching commands",
            escClearsQueryFirst: false
        ))
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        // Scrim: swallow clicks; a click outside the card dismisses (§Phase-0
        // lighting model: modals get a dimmed scrim).
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

        // Light from above: the 1 px top hairline of a floating surface.
        let topHairline = NSBox()
        topHairline.boxType = .custom
        topHairline.fillColor = Theme.Elevation.hairline
        topHairline.borderWidth = 0
        topHairline.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(topHairline)

        summon.translatesAutoresizingMaskIntoConstraints = false
        summon.onActivate = { [weak self] item in self?.run(at: Int(item.id) ?? -1) }
        summon.onEscape = { [weak self] in self?.onDismiss() }
        summon.onContentChange = { [weak self] in self?.trackContentHeight() }
        card.addSubview(summon)

        NSLayoutConstraint.activate([
            cardHost.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardHost.widthAnchor.constraint(equalToConstant: 560),

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            summon.topAnchor.constraint(equalTo: card.topAnchor),
            summon.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            summon.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            summon.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        // Items are keyed by position, not command id — dynamic commands can
        // collide on id (two projects with the same window title), and the row
        // the user picked must be the row that runs.
        summon.setItems(commands.enumerated().map { index, command in
            SummonItem(
                id: String(index),
                // Command names are Atelier speaking (§1.4); chords are keycaps.
                text: NSAttributedString(string: command.title, attributes: [
                    .font: Theme.Typography.ui(Theme.Typography.body),
                    .foregroundColor: Theme.chromeText,
                ]),
                matchText: command.title.lowercased(),
                chord: command.key
            )
        })
        // The initial height lands before the first layout, so the descent
        // animation starts from the settled size.
        let height = summon.makeListHeightConstraint(constant: min(summon.contentHeight, 300))
        height.isActive = true
        listHeight = height
    }

    /// The panel height tracks the results as you type (§6 — the single
    /// biggest "native" tell).
    private func trackContentHeight() {
        let newHeight = min(summon.contentHeight, 300)
        guard let listHeight, listHeight.constant != newHeight else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            listHeight.constant = newHeight
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                listHeight.animator().constant = newHeight
                self.layoutSubtreeIfNeeded()
            }
        }
    }

    private func run(at index: Int) {
        guard commands.indices.contains(index) else { return }
        let command = commands[index]
        RecentCommands.bump(command.id)
        onDismiss()
        command.action()
    }

    /// The Spotlight descent (§6): the card drops in from the titlebar edge,
    /// settling in ~180 ms. Reduce Motion gets a plain appear.
    func animateIn() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        layoutSubtreeIfNeeded()
        let target = cardHost.frame
        cardHost.frame = target.offsetBy(dx: 0, dy: 10) // AppKit y-up: start higher
        cardHost.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            cardHost.animator().frame = target
            cardHost.animator().alphaValue = 1
        }
    }

    /// The view to focus once presented.
    var focusField: NSView { summon.focusField }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !cardHost.frame.contains(point) { onDismiss() }
    }
}

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
final class CommandPalette: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private let commands: [PaletteCommand]
    private var filtered: [PaletteCommand]
    private let onDismiss: () -> Void

    /// Carries the floating shadow; the card itself masks to its rounded
    /// corners, which would clip a shadow set on its own layer.
    private let cardHost = NSView()
    private let card = NSVisualEffectView()
    private let field = NSTextField()
    private let table = PaletteTableView()
    private let highlight = SlidingSelectionHighlight()
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
        self.filtered = self.commands
        self.onDismiss = onDismiss
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

        field.placeholderString = "Type a command…"
        field.font = Theme.Typography.ui(Theme.Typography.large)
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = Theme.chromeText
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(field)

        let divider = NSBox()
        divider.boxType = .custom
        divider.fillColor = Theme.Elevation.frameLine
        divider.borderWidth = 0
        divider.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(divider)

        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 28
        table.backgroundColor = .clear
        table.style = .plain
        table.target = self
        table.action = #selector(rowClicked)
        table.onReturn = { [weak self] in self?.runSelected() }
        table.onEscape = { [weak self] in self?.onDismiss() }
        table.addTableColumn(NSTableColumn(identifier: .init("command")))

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll)

        NSLayoutConstraint.activate([
            cardHost.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardHost.widthAnchor.constraint(equalToConstant: 560),
            cardHost.heightAnchor.constraint(lessThanOrEqualToConstant: 360),

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            field.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            divider.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        let height = scroll.heightAnchor.constraint(equalToConstant: Self.listHeight(for: filtered.count))
        height.isActive = true
        listHeight = height

        highlight.attach(to: table)
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        table.layoutSubtreeIfNeeded()
        highlight.update(for: table, animated: false)
    }

    private static func listHeight(for rows: Int) -> CGFloat {
        min(CGFloat(rows) * 28 + 8, 300)
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
    var focusField: NSView { field }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !cardHost.frame.contains(point) { onDismiss() }
    }

    // MARK: Filtering

    private func refilter() {
        let query = field.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        filtered = query.isEmpty
            ? commands
            : commands.filter { fuzzyMatches(query: query, candidate: $0.title.lowercased()) }
        table.reloadData()
        if !filtered.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }

        // The panel height tracks the results as you type (§6 — the single
        // biggest "native" tell). The row set changed, so the highlight jumps
        // rather than gliding to an unrelated row.
        table.layoutSubtreeIfNeeded()
        highlight.update(for: table, animated: false)
        let newHeight = Self.listHeight(for: filtered.count)
        if let listHeight, listHeight.constant != newHeight {
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
    }

    /// Subsequence match — `wt` finds "Worktree: …", `tl` finds "Toggle Layout".
    private func fuzzyMatches(query: String, candidate: String) -> Bool {
        var i = candidate.startIndex
        for ch in query {
            guard let found = candidate[i...].firstIndex(of: ch) else { return false }
            i = candidate.index(after: found)
        }
        return true
    }

    private func runSelected() {
        guard filtered.indices.contains(table.selectedRow) else { return }
        let command = filtered[table.selectedRow]
        RecentCommands.bump(command.id)
        onDismiss()
        command.action()
    }

    @objc private func rowClicked() { runSelected() }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            runSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss()
            return true
        case #selector(NSResponder.moveDown(_:)):
            table.selectRowIndexes([min(table.selectedRow + 1, filtered.count - 1)], byExtendingSelection: false)
            table.scrollRowToVisible(table.selectedRow)
            highlight.update(for: table, animated: true)
            return true
        case #selector(NSResponder.moveUp(_:)):
            table.selectRowIndexes([max(table.selectedRow - 1, 0)], byExtendingSelection: false)
            table.scrollRowToVisible(table.selectedRow)
            highlight.update(for: table, animated: true)
            return true
        default:
            return false
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let command = filtered[row]
        let cell = NSTableCellView()

        // Command names are Atelier speaking (§1.4); the chord is keycap
        // content, so mono. (Full keycap chips land in Phase 4.)
        let title = NSTextField(labelWithString: command.title)
        title.font = Theme.Typography.ui(Theme.Typography.body)
        title.textColor = Theme.chromeText
        title.lineBreakMode = .byTruncatingTail
        title.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 14),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        if let key = command.key {
            // Chords as keycap chips (§6), per Theme.Typography.Keycap.
            let chord = KeycapChipView(chord: key)
            cell.addSubview(chord)
            NSLayoutConstraint.activate([
                chord.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -14),
                chord.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                title.trailingAnchor.constraint(lessThanOrEqualTo: chord.leadingAnchor, constant: -10),
            ])
        } else {
            title.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -14).isActive = true
        }
        return cell
    }
}

/// Return runs, Escape dismisses — instead of the system beep.
private final class PaletteTableView: NSTableView {
    var onReturn: (() -> Void)?
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36: onReturn?()
        case 53: onEscape?()
        default: super.keyDown(with: event)
        }
    }
}

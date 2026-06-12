import AppKit

/// One row of the worktree fan: the worktree plus its live state.
struct WorktreeFanRow {
    let worktree: Worktree
    let isOpen: Bool   // a session tab exists on this root
    let isDirty: Bool  // uncommitted changes
}

/// The worktree fan (MILESTONE_1 §6): rises from the bottom-left pill in an
/// `NSPopover`. Type to filter — or to name a new worktree (top action row);
/// Enter / click returns to a worktree; the `×` asks before tearing one down.
final class WorktreeFanController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    var onOpen: ((Worktree) -> Void)?
    var onCreate: ((String) -> Void)?
    var onRemove: ((WorktreeFanRow) -> Void)?
    var onDismiss: (() -> Void)?

    /// First-responder target for the overlay host.
    var filterField: NSView { field }

    private var allRows: [WorktreeFanRow]
    private var filtered: [WorktreeFanRow]
    private let field = NSTextField()
    private let table = FanTableView()
    private let highlight = SlidingSelectionHighlight()
    private var rootHeight: NSLayoutConstraint?

    /// Pre-filled filter text — the orphan-restore notice opens the fan aimed
    /// at recreating a named worktree (POLISH_PLAN §5).
    var prefill: String?

    /// True when the typed text names no existing branch — the first row becomes
    /// "create …".
    private var showsCreateRow: Bool {
        let text = trimmedQuery
        guard !text.isEmpty else { return false }
        return !allRows.contains { $0.worktree.branch == text }
    }

    private var trimmedQuery: String {
        field.stringValue.trimmingCharacters(in: .whitespaces)
    }

    init(rows: [WorktreeFanRow]) {
        self.allRows = rows
        self.filtered = rows
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 0))

        field.placeholderString = "filter, or name a new worktree…"
        field.font = Theme.Typography.ui(Theme.Typography.body)
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(field)

        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 26
        table.backgroundColor = .clear
        table.style = .plain
        table.target = self
        table.action = #selector(rowClicked)
        table.onReturn = { [weak self] in self?.activateSelection() }
        table.onEscape = { [weak self] in self?.onDismiss?() }
        let column = NSTableColumn(identifier: .init("worktree"))
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let height = root.heightAnchor.constraint(equalToConstant: Self.contentHeight(forRows: filtered.count))
        rootHeight = height
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 320),
            height,
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        view = root
        highlight.attach(to: table)
        if let prefill {
            field.stringValue = prefill
        }
        reload()
    }

    private static func contentHeight(forRows rows: Int) -> CGFloat {
        min(CGFloat(max(rows, 1)) * 26 + 46, 320)
    }

    /// Refresh the dirty markers once the off-main `git status` sweep lands
    /// (§6: the fan opens next frame; truth arrives a beat later).
    func updateDirty(_ dirtyByPath: [String: Bool]) {
        allRows = allRows.map { row in
            WorktreeFanRow(
                worktree: row.worktree,
                isOpen: row.isOpen,
                isDirty: dirtyByPath[row.worktree.path] ?? row.isDirty
            )
        }
        let selected = table.selectedRow
        reload(keepingSelection: selected)
    }

    private func reload(keepingSelection: Int? = nil) {
        let query = trimmedQuery.lowercased()
        filtered = query.isEmpty
            ? allRows
            : allRows.filter { $0.worktree.branch.lowercased().contains(query) }
        table.reloadData()
        if numberOfRows(in: table) > 0 {
            let row = min(keepingSelection ?? 0, numberOfRows(in: table) - 1)
            table.selectRowIndexes([max(row, 0)], byExtendingSelection: false)
        }
        table.layoutSubtreeIfNeeded()
        highlight.update(for: table, animated: false)

        // Panel height tracks the filtered results (§6) — animated once the
        // fan is on screen, instant during loadView.
        let newHeight = Self.contentHeight(forRows: numberOfRows(in: table))
        if let rootHeight, rootHeight.constant != newHeight {
            if view.superview == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                rootHeight.constant = newHeight
            } else {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    ctx.allowsImplicitAnimation = true
                    rootHeight.animator().constant = newHeight
                    view.superview?.layoutSubtreeIfNeeded()
                }
            }
        }
    }

    /// Open / create whatever the current selection means.
    private func activateSelection() {
        let row = table.selectedRow
        if showsCreateRow {
            if row == 0 { onCreate?(trimmedQuery); return }
            let index = row - 1
            if filtered.indices.contains(index) { onOpen?(filtered[index].worktree) }
        } else if filtered.indices.contains(row) {
            onOpen?(filtered[row].worktree)
        }
    }

    @objc private func rowClicked() {
        // Single click on the row body opens; the × has its own button.
        activateSelection()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) { reload() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            activateSelection()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
            return true
        case #selector(NSResponder.moveDown(_:)):
            table.selectRowIndexes([min(table.selectedRow + 1, numberOfRows(in: table) - 1)], byExtendingSelection: false)
            highlight.update(for: table, animated: true)
            return true
        case #selector(NSResponder.moveUp(_:)):
            table.selectRowIndexes([max(table.selectedRow - 1, 0)], byExtendingSelection: false)
            highlight.update(for: table, animated: true)
            return true
        default:
            return false
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count + (showsCreateRow ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if showsCreateRow && row == 0 {
            // The §1.4 signature move: Atelier speaks ("create"), the branch
            // name is inset in mono.
            return Self.label(attributed: {
                let text = NSMutableAttributedString()
                text.append(NSAttributedString(string: "＋ create ", attributes: [
                    .font: Theme.Typography.ui(Theme.Typography.body),
                    .foregroundColor: Theme.accentGreen,
                ]))
                text.append(NSAttributedString(string: "⎇ \(trimmedQuery)", attributes: [
                    .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
                    .foregroundColor: Theme.chromeText,
                ]))
                return text
            }())
        }

        let index = showsCreateRow ? row - 1 : row
        guard filtered.indices.contains(index) else { return nil }
        let fanRow = filtered[index]

        let text = NSMutableAttributedString()
        // Branch names are mono (§1.4); the state words are Atelier speaking.
        text.append(NSAttributedString(string: "⎇ \(fanRow.worktree.branch)", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeText,
        ]))
        var marks: [String] = []
        if fanRow.worktree.isPrimary { marks.append("primary") }
        if fanRow.isOpen { marks.append("open") }
        if fanRow.isDirty { marks.append("dirty") }
        if !marks.isEmpty {
            text.append(NSAttributedString(string: "  \(marks.joined(separator: " · "))", attributes: [
                .font: Theme.Typography.ui(Theme.Typography.small),
                .foregroundColor: fanRow.isDirty ? Theme.accentBlue : Theme.chromeMutedText,
            ]))
        }

        let cell = Self.label(attributed: text)

        // The primary checkout is not removable; everything else gets the ×.
        if !fanRow.worktree.isPrimary {
            let close = NSButton()
            close.bezelStyle = .regularSquare
            close.isBordered = false
            close.imagePosition = .imageOnly
            close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove worktree")
            close.symbolConfiguration = .init(pointSize: 9, weight: .medium)
            close.contentTintColor = Theme.chromeMutedText
            close.target = self
            close.action = #selector(removeTapped(_:))
            close.tag = index
            close.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(close)
            NSLayoutConstraint.activate([
                close.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                close.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    @objc private func removeTapped(_ sender: NSButton) {
        guard filtered.indices.contains(sender.tag) else { return }
        onRemove?(filtered[sender.tag])
    }

    private static func label(attributed: NSAttributedString) -> NSTableCellView {
        let label = NSTextField(labelWithAttributedString: attributed)
        label.lineBreakMode = .byTruncatingTail
        let cell = NSTableCellView()
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -28),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// Table that reports Return/Escape instead of beeping (same idiom as the
/// Landing list).
private final class FanTableView: NSTableView {
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

/// The fan's host (§6): a transparent in-window overlay whose card *rises from
/// the pill* — scale from 0.96 anchored at its bottom-left, settling in
/// ≤150 ms — wearing the lighting model (top hairline, the floating shadow).
/// No scrim: the fan is a speed surface, not a modal. Replaces the NSPopover,
/// whose stock chrome and appear animation belonged to a different app.
final class WorktreeFanOverlay: NSView {
    private let controller: WorktreeFanController
    private let cardHost = NSView()
    private let card = NSVisualEffectView()
    private let onDismiss: () -> Void

    /// The view to focus once presented.
    var focusField: NSView { controller.filterField }

    init(controller: WorktreeFanController, onDismiss: @escaping () -> Void) {
        self.controller = controller
        self.onDismiss = onDismiss
        super.init(frame: .zero)

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

        let content = controller.view
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        card.addSubview(topHairline)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Pin the card just above the pill (frames in this overlay's coordinate
    /// space) and rise. The card grows upward from the pill as results change,
    /// so the *bottom* edge is the anchored one.
    func present(abovePillFrame pill: CGRect) {
        // `pill` is in this overlay's (y-up) coordinates: pill.maxY is the
        // pill's top measured from the bottom edge — a negative bottom-anchor
        // constant raises the card that far.
        NSLayoutConstraint.activate([
            cardHost.leadingAnchor.constraint(equalTo: leadingAnchor, constant: max(8, pill.minX - 4)),
            cardHost.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(pill.maxY + 8)),
        ])
        layoutSubtreeIfNeeded()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let target = cardHost.frame
        // Scale 0.96 anchored at the bottom-left corner (the pill's corner).
        cardHost.frame = CGRect(
            x: target.minX,
            y: target.minY,
            width: target.width * 0.96,
            height: target.height * 0.96
        )
        cardHost.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            cardHost.animator().frame = target
            cardHost.animator().alphaValue = 1
        }
    }

    /// Click outside the card dismisses; the fan swallows nothing else.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !cardHost.frame.contains(point) { onDismiss() }
    }
}

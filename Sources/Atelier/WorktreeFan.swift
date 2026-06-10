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

    private let allRows: [WorktreeFanRow]
    private var filtered: [WorktreeFanRow]
    private let field = NSTextField()
    private let table = FanTableView()

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
        field.font = .systemFont(ofSize: 12)
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
        let column = NSTableColumn(identifier: .init("worktree"))
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let height = min(CGFloat(max(filtered.count, 1)) * 26 + 46, 320)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: 320),
            root.heightAnchor.constraint(equalToConstant: height),
            field.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            field.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -4),
        ])
        view = root
        reload()
    }

    private func reload() {
        let query = trimmedQuery.lowercased()
        filtered = query.isEmpty
            ? allRows
            : allRows.filter { $0.worktree.branch.lowercased().contains(query) }
        table.reloadData()
        if numberOfRows(in: table) > 0 {
            table.selectRowIndexes([0], byExtendingSelection: false)
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
        case #selector(NSResponder.moveDown(_:)):
            table.selectRowIndexes([min(table.selectedRow + 1, numberOfRows(in: table) - 1)], byExtendingSelection: false)
            return true
        case #selector(NSResponder.moveUp(_:)):
            table.selectRowIndexes([max(table.selectedRow - 1, 0)], byExtendingSelection: false)
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
            return Self.label(attributed: {
                let text = NSMutableAttributedString()
                text.append(NSAttributedString(string: "＋ create ", attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: Theme.accentGreen,
                ]))
                text.append(NSAttributedString(string: "⎇ \(trimmedQuery)", attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: Theme.chromeText,
                ]))
                return text
            }())
        }

        let index = showsCreateRow ? row - 1 : row
        guard filtered.indices.contains(index) else { return nil }
        let fanRow = filtered[index]

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "⎇ \(fanRow.worktree.branch)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: Theme.chromeText,
        ]))
        var marks: [String] = []
        if fanRow.worktree.isPrimary { marks.append("primary") }
        if fanRow.isOpen { marks.append("open") }
        if fanRow.isDirty { marks.append("dirty") }
        if !marks.isEmpty {
            text.append(NSAttributedString(string: "  \(marks.joined(separator: " · "))", attributes: [
                .font: NSFont.systemFont(ofSize: 10),
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

/// Table that reports Return instead of beeping (same idiom as the Landing list).
private final class FanTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

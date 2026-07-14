import AppKit

/// The summon idiom (interaction pass, 2026-07-13): one shared type-to-choose
/// surface — a borderless field over a fuzzy-filtered list with the sliding
/// highlight — so every "open something" gesture in the app is the same
/// gesture. The command palette floats it in a card; the Landing embeds it in
/// the pane; the M2 `⌘P` picker inherits it.
///
/// The field owns keyboard focus for the surface's whole life: the first
/// keystroke always lands in it, arrows move the selection, `↩` activates,
/// `Esc` escapes (optionally clearing the query first), and a single click
/// activates a row without stealing focus — the table refuses first-responder
/// so typing never stops working. Row 0 re-selects on every keystroke so `↩`
/// always has a target; when nothing matches, the surface says so instead of
/// collapsing to a sliver.

/// One row a summon surface can offer. The host owns the row's voice (§1.4):
/// mono for terminal-pasteable content, ui for Atelier speaking.
struct SummonItem {
    let id: String
    /// Fully styled row text.
    let text: NSAttributedString
    /// Lowercased haystack the fuzzy query runs against.
    let matchText: String
    /// Optional trailing keycap chord (the surface teaches the keymap).
    let chord: String?
}

/// Subsequence match — `wt` finds "worktree: …", `tl` finds "toggle layout".
/// `query` and `candidate` are expected lowercased.
func fuzzyMatches(query: String, candidate: String) -> Bool {
    var i = candidate.startIndex
    for ch in query {
        guard let found = candidate[i...].firstIndex(of: ch) else { return false }
        i = candidate.index(after: found)
    }
    return true
}

final class SummonList: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    /// Geometry + copy that differ per host; the interaction never does.
    struct Style {
        let placeholder: String
        let fieldFont: NSFont
        /// The placeholder is Atelier speaking, so it may take the ui voice
        /// even when the typed query is mono (§1.4). Nil = fieldFont.
        let placeholderFont: NSFont?
        let rowHeight: CGFloat
        let rowInset: CGFloat
        let noMatchText: String
        /// `Esc` with a live query clears it first (Raycast); a second `Esc`
        /// reaches `onEscape`. Off = `Esc` escapes immediately (VSCode palette).
        let escClearsQueryFirst: Bool
        /// On = the list fuzzy-filters its items against the query (palette,
        /// landing, ⌘P). Off = the query *produces* the items — the host
        /// listens on `onQueryChange` and calls `setItems` with fresh results
        /// (⌘⇧F repo search).
        var filtersLocally: Bool = true
    }

    var onActivate: ((SummonItem) -> Void)?
    var onEscape: (() -> Void)?
    /// Fired whenever the filtered row set changes — hosts that size themselves
    /// to the content (the palette card) track it; embedded hosts ignore it.
    var onContentChange: (() -> Void)?
    /// The query changed. Externally-filtered surfaces (`filtersLocally:
    /// false`) *must* listen and produce a new offer; locally-filtered hosts
    /// *may* listen to augment theirs (the Landing's `host:dir` row).
    var onQueryChange: ((String) -> Void)?
    /// Optional match ranking for locally-filtered hosts (⌘P: basename hits
    /// outrank path-scatter hits). Higher wins; ties keep provider order.
    var rank: ((SummonItem, String) -> Int)?

    var focusField: NSView { field }
    private(set) var query = ""

    /// Natural height of the list area: the rows, or the one-line no-match
    /// state — never a collapsed sliver.
    var contentHeight: CGFloat {
        let rows = filtered.isEmpty && !query.isEmpty ? 1 : filtered.count
        return CGFloat(rows) * style.rowHeight + 8
    }

    private let style: Style
    private let field = NSTextField()
    private let table = SummonTableView()
    private let scroll = NSScrollView()
    private let highlight = SlidingSelectionHighlight()
    private let noMatchLabel = NSTextField(labelWithString: "")
    private var items: [SummonItem] = []
    private var filtered: [SummonItem] = []

    /// For hosts that hug the content (the palette card): a height constraint
    /// on the list area, driven by the host from `contentHeight`. Embedded
    /// hosts skip this and let the list fill.
    func makeListHeightConstraint(constant: CGFloat) -> NSLayoutConstraint {
        scroll.heightAnchor.constraint(equalToConstant: constant)
    }

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        field.placeholderAttributedString = NSAttributedString(string: style.placeholder, attributes: [
            .font: style.placeholderFont ?? style.fieldFont,
            .foregroundColor: Theme.chromeMutedText,
        ])
        field.font = style.fieldFont
        field.focusRingType = .none
        field.isBezeled = false
        field.drawsBackground = false
        field.textColor = Theme.chromeText
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)

        let divider = NSBox()
        divider.boxType = .custom
        divider.fillColor = Theme.Elevation.frameLine
        divider.borderWidth = 0
        divider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)

        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = style.rowHeight
        table.backgroundColor = .clear
        table.style = .plain
        // A click below the last row must not clear the selection — the
        // highlight would keep showing a row that `↩` no longer targets.
        table.allowsEmptySelection = false
        table.target = self
        table.action = #selector(rowClicked)
        table.addTableColumn(NSTableColumn(identifier: .init("summon")))

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        // The no-match state: one honest muted line where row 0 would be.
        noMatchLabel.stringValue = style.noMatchText
        noMatchLabel.font = Theme.Typography.ui(Theme.Typography.body)
        noMatchLabel.textColor = Theme.chromeMutedText
        noMatchLabel.isHidden = true
        noMatchLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(noMatchLabel)

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            divider.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            noMatchLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            noMatchLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: style.rowInset + 6),
            noMatchLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -style.rowInset),
        ])

        field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14).isActive = true

        highlight.attach(to: table)
    }

    /// Replace the offer. The live query is preserved and re-applied, and so
    /// is the user's selection (by id) — a background refresh never eats what
    /// they typed or where they'd arrowed to.
    func setItems(_ items: [SummonItem]) {
        let keep = filtered.indices.contains(table.selectedRow) ? filtered[table.selectedRow].id : nil
        self.items = items
        refilter(preserving: keep)
    }

    // MARK: Filtering

    private func refilter(preserving keepId: String? = nil) {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        filtered = (q.isEmpty || !style.filtersLocally)
            ? items
            : items.filter { fuzzyMatches(query: q, candidate: $0.matchText) }
        if let rank, !q.isEmpty, style.filtersLocally {
            filtered = filtered.enumerated()
                .sorted { a, b in
                    let ra = rank(a.element, q), rb = rank(b.element, q)
                    return ra != rb ? ra > rb : a.offset < b.offset
                }
                .map(\.element)
        }
        table.reloadData()
        noMatchLabel.isHidden = !(filtered.isEmpty && !q.isEmpty)
        if let keepId, let row = filtered.firstIndex(where: { $0.id == keepId }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else if !filtered.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }

        // The row set changed, so the highlight jumps rather than gliding to
        // an unrelated row.
        table.layoutSubtreeIfNeeded()
        highlight.update(for: table, animated: false)
        onContentChange?()
    }

    private func activateSelected() {
        guard filtered.indices.contains(table.selectedRow) else { return }
        onActivate?(filtered[table.selectedRow])
    }

    @objc private func rowClicked() {
        // A click on dead space (below the rows) reports clickedRow -1; with
        // the selection preserved, acting on it would activate a row the user
        // didn't click.
        guard table.clickedRow >= 0 else { return }
        activateSelected()
    }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        query = field.stringValue
        onQueryChange?(query)
        refilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            activateSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if style.escClearsQueryFirst, !query.isEmpty {
                field.stringValue = ""
                query = ""
                refilter()
            } else {
                onEscape?()
            }
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !filtered.isEmpty else { return true }
            table.selectRowIndexes([min(table.selectedRow + 1, filtered.count - 1)], byExtendingSelection: false)
            table.scrollRowToVisible(table.selectedRow)
            highlight.update(for: table, animated: true)
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard !filtered.isEmpty else { return true }
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
        let item = filtered[row]
        let cell = NSTableCellView()

        let title = NSTextField(labelWithAttributedString: item.text)
        title.lineBreakMode = .byTruncatingTail
        title.cell?.usesSingleLineMode = true
        title.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: style.rowInset),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        if let key = item.chord {
            let chord = KeycapChipView(chord: key)
            cell.addSubview(chord)
            NSLayoutConstraint.activate([
                chord.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -style.rowInset),
                chord.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                title.trailingAnchor.constraint(lessThanOrEqualTo: chord.leadingAnchor, constant: -10),
            ])
        } else {
            title.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -style.rowInset).isActive = true
        }
        return cell
    }
}

/// The summon list never takes keyboard focus — the field keeps it, so typing
/// keeps filtering no matter what was last clicked. Clicks still select and
/// activate via the table's target/action.
private final class SummonTableView: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

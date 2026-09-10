import AppKit

protocol BottomBarDelegate: AnyObject {
    func bottomBarDidSelectSession(at index: Int)
    func bottomBarDidRequestNewSession()
    func bottomBarDidRequestCloseSession(at index: Int)
    /// Inline rename finished. `title` is the committed text (nil = revert to
    /// the live auto title); a cancelled rename never reaches this.
    func bottomBarDidRenameSession(at index: Int, title: String?)
    func bottomBarDidToggleLayout()
    /// Right-click on a worktree folder's label: tear the worktree down.
    func bottomBarDidRequestRemoveWorktree(at path: String)
    /// The gear at the bar's far right.
    func bottomBarDidRequestSettings()
    /// A tab was dragged to a new place: the full strip order, by session id.
    func bottomBarDidReorderSessions(order: [UUID])
}

/// Everything one session tab needs to draw. `id` is the session's stable
/// identity (tab views persist across updates so state changes can animate);
/// `index` is its position in the window's session list at this instant.
struct SessionTabInfo {
    let id: UUID
    let index: Int
    let title: String
    let isWorktree: Bool
    /// Set for remote sessions: the ssh host, worn on the tab (`@host`) the
    /// way ⎇ marks a worktree — where the work lives, always visible.
    let remoteHost: String?
    /// Group boundary marker — tabs sharing a root sit together (MILESTONE_1 §7);
    /// the grouping *is* how codebase sharing is shown.
    let groupKey: String
    /// What the group's folder tab says (branch, `⎇ worktree`, `@host`).
    let groupLabel: String
    let attention: Session.Attention
    /// When the attention state began — surfaced only in the hover tooltip
    /// (§1.3: time on inquiry, never pushed).
    let attentionSince: Date?
}

/// The bottom bar (MILESTONE_1 §7, revised 2026-09-03). Static project pill
/// on the left, session tabs in the middle — each root's tabs sitting inside a
/// **folder**: a cell with a small label tab rising from its top-left edge
/// naming the worktree (main's branch, `⎇ dir`, `@host`). Wraps to a second
/// row group-aware when full, with a `»` overflow menu as the hard ceiling —
/// and the clock, layout toggle, and settings gear on the right. Styling
/// follows the tmux status bar this app succeeds: blue pill, green active tab,
/// dark text on both.
///
/// Tab views are *persistent* (keyed by session id) and laid out by hand, so
/// width changes glide (a Claude title rewrite slides neighbors instead of
/// twitching them) and attention changes cross-fade in place.
final class BottomBar: NSView {
    weak var delegate: BottomBarDelegate?

    /// Bar heights. One row is the tmux-status-bar 30: the folder label tabs
    /// poke *up past the bar's top edge* over the pane content (owner call
    /// 2026-09-07) rather than thickening the bar. Two rows house the lower
    /// row's label band between the rows.
    static let rowHeight: CGFloat = 30
    static let twoRowHeight: CGFloat = 72
    /// How far the top row's label tabs rise past the backdrop. The bar's
    /// *frame* includes this band (AppKit clips hit-tests, tracking areas,
    /// and cursor rects to a view's visible bounds); the band is transparent
    /// and passes pointer events through to the pane beneath except over a
    /// label. Owners size the bar `desiredHeight + overhang` and overlap the
    /// session area by `overhang`.
    static var overhang: CGFloat { folderTabHeight }
    private static let tabHeight: CGFloat = 20
    private static let tabGap: CGFloat = 4
    private static let rowGap: CGFloat = 4
    /// Folder anatomy: the cell hugs its tabs by `folderPadX`/`folderPadY`;
    /// the label tab rises `folderTabHeight` above the cell.
    private static let folderPadX: CGFloat = 6
    private static let folderPadY: CGFloat = 2
    private static let folderTabHeight: CGFloat = 13
    private static let folderGap: CGFloat = 10
    private static let buttonGap: CGFloat = 6
    private static var cellHeight: CGFloat { tabHeight + folderPadY * 2 }
    /// Row pitch: a cell, the gap, and the lower row's label band.
    private static var rowPitch: CGFloat { cellHeight + rowGap + folderTabHeight }
    /// Where the bottom row's tabs are centered, measured from the bar's
    /// bottom edge — the pill, clock, and buttons sit on this axis.
    private static var bottomRowAxis: CGFloat { 15 }

    /// The bar's current natural height (one or two tab rows).
    private(set) var desiredHeight: CGFloat = BottomBar.rowHeight
    /// Fired when `desiredHeight` changes so the owner can resize the constraint.
    var onDesiredHeightChange: ((CGFloat) -> Void)?

    private let pillView = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    /// Manual-layout home of the tab views; sits between pill and clock.
    private let tabsArea = TabsAreaView()
    private let addButton = NSButton()
    private let overflowButton = NSButton()
    private let clockPrefixLabel = NSTextField(labelWithString: "")
    private let clockColonLabel = BreathingColonLabel(labelWithString: ":")
    private let clockSuffixLabel = NSTextField(labelWithString: "")
    private let layoutButton = NSButton()
    private let settingsButton = NSButton()
    private let topBorder = NSBox()
    /// The mantle field — the visible bar. Pinned to the bottom `desiredHeight`.
    private let backdrop = NSView()
    private var backdropHeight: NSLayoutConstraint?

    private var tabs: [SessionTabInfo] = []
    private var activeIndex = 0
    private var tabViews: [UUID: SessionTabView] = [:]
    private var folderViews: [String: FolderView] = [:]
    private var foldersVisible = true
    private var lastFlowWidth: CGFloat = 0
    private var lastFlowHeight: CGFloat = 0
    /// First population per launch gets the restore stagger (§5); afterwards
    /// arrivals appear with a plain fade, never again.
    private var hasRevealed = false

    private var clockTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        build()
        startClock()
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        clockTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    override func updateLayer() {
        backdrop.layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        backdrop.layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    /// The overhang band is transparent: a point up there is the pane's unless
    /// a folder label tab is under it (owner report 2026-09-07).
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if let hit = tabsArea.hitTest(tabsArea.convert(local, from: self), outsideFrame: true) {
            return hit
        }
        if local.y > desiredHeight { return nil }
        return super.hitTest(point)
    }

    /// The window moves by its background (`isMovableByWindowBackground`), and
    /// a non-opaque view says yes to that by default — which would let a tab
    /// drag haul the whole window along. The bar is controls, not a handle.
    override var mouseDownCanMoveWindow: Bool { false }

    private func build() {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdrop)
        topBorder.boxType = .custom
        topBorder.fillColor = Theme.Elevation.frameLine
        topBorder.borderWidth = 0
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = Theme.accentBlue.cgColor
        pillView.layer?.cornerRadius = Theme.Elevation.radiusSmall
        pillView.translatesAutoresizingMaskIntoConstraints = false
        // Retired 2026-09-07, restored 2026-09-08 (owner: "an anchor") — the
        // static project name at the bar's left edge, redundant on purpose.
        addSubview(pillView)

        // The pill carries the project name — a path component, so mono (§1.4).
        // Body size across the whole bar (owner call 2026-07-13): the tmux
        // status bar this succeeds runs at terminal size, and 11 pt read as a
        // downgrade next to it.
        pillLabel.font = Theme.Typography.mono(Theme.Typography.body, weight: .semibold)
        pillLabel.textColor = Theme.accentTextDark
        pillLabel.lineBreakMode = .byTruncatingMiddle
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(pillLabel)

        tabsArea.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabsArea)

        configureIconButton(addButton, symbol: "plus", action: #selector(addTapped))
        tabsArea.addSubview(addButton)
        configureIconButton(overflowButton, symbol: "chevron.right.2", action: nil)
        overflowButton.isHidden = true
        tabsArea.addSubview(overflowButton)

        // The clock is mono (§1.4) with the colon split out so it can breathe
        // (§1.1 motion inventory item 3: ~1 Hz opacity ease — a breath, not a
        // blink). JetBrains Mono keeps the line from shifting under it.
        for label in [clockPrefixLabel, clockColonLabel, clockSuffixLabel] {
            label.font = Theme.Typography.mono(Theme.Typography.body)
            label.textColor = Theme.chromeMutedText
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        configureIconButton(layoutButton, symbol: "rectangle.split.3x1", action: #selector(layoutTapped))
        // The toggle and gear are constraint-anchored (unlike the flow-placed
        // buttons, which are positioned by frame inside tabsArea).
        layoutButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutButton)
        configureIconButton(settingsButton, symbol: "gearshape", action: #selector(settingsTapped))
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(settingsButton)

        let backdropTop = backdrop.heightAnchor.constraint(equalToConstant: Self.rowHeight)
        backdropTop.priority = NSLayoutConstraint.Priority(999)
        backdropHeight = backdropTop
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            backdropTop,
            topBorder.topAnchor.constraint(equalTo: backdrop.topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),


            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            settingsButton.widthAnchor.constraint(equalToConstant: 22),
            settingsButton.heightAnchor.constraint(equalToConstant: 22),
            layoutButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -4),
            layoutButton.widthAnchor.constraint(equalToConstant: 22),
            layoutButton.heightAnchor.constraint(equalToConstant: 22),

            // One cap-height (§3 micro-pass): same mono face and size as the
            // pill label, centered on the same axis — identical baselines
            // without cross-branch baseline constraints (which AppKit's
            // window-sizing pass mishandles; see the tabsArea note below).
            clockSuffixLabel.trailingAnchor.constraint(equalTo: layoutButton.leadingAnchor, constant: -12),
            clockColonLabel.trailingAnchor.constraint(equalTo: clockSuffixLabel.leadingAnchor),
            clockPrefixLabel.trailingAnchor.constraint(equalTo: clockColonLabel.leadingAnchor),

            pillView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pillView.heightAnchor.constraint(equalToConstant: Self.tabHeight),
            pillLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 8),
            pillLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -8),
            pillLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            pillLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            tabsArea.leadingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: 14),
            tabsArea.trailingAnchor.constraint(lessThanOrEqualTo: clockPrefixLabel.leadingAnchor, constant: -12),
        ])
        // The trailing equality must NOT be required: a closed required chain
        // from leading to trailing lets AppKit "resolve" the window width from
        // constraints (it collapsed the window to ~10 pt). Stretch by desire.
        let stretch = tabsArea.trailingAnchor.constraint(equalTo: clockPrefixLabel.leadingAnchor, constant: -12)
        stretch.priority = .defaultLow
        // And the vertical pins yield while the bar is hidden at height 0.
        // tabsArea spans the whole frame, overhang band included, so its
        // children's tracking areas survive up there.
        let top = tabsArea.topAnchor.constraint(equalTo: topAnchor)
        top.priority = NSLayoutConstraint.Priority(999)
        let bottom = tabsArea.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottom.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([stretch, top, bottom])
        // Everything outside the flow sits on the bottom tab row's axis — the
        // folder label band above it is the tabs' own business. These yield
        // too while the bar is hidden at height 0.
        for view in [pillView, clockPrefixLabel, clockColonLabel, clockSuffixLabel, layoutButton, settingsButton] {
            let axis = view.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -Self.bottomRowAxis)
            axis.priority = NSLayoutConstraint.Priority(999)
            axis.isActive = true
        }
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector?) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = Theme.chromeMutedText
        button.target = self
        button.action = action
    }

    // MARK: Update

    func update(tabs: [SessionTabInfo], activeIndex: Int, pill: String, mode: LayoutMode?) {
        if drag != nil || groupDrag != nil {
            // Mid-drag the strip's order is the pointer's, not the owner's
            // (the title timer refreshes every 2 s): keep the local order.
            let rank = Dictionary(uniqueKeysWithValues: self.tabs.enumerated().map { ($1.id, $0) })
            self.tabs = tabs.sorted { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        } else {
            self.tabs = tabs
        }
        self.activeIndex = activeIndex

        pillLabel.stringValue = pill
        pillView.isHidden = pill.isEmpty

        layoutButton.isHidden = mode == nil
        let symbol: String
        switch mode {
        case .triptych: symbol = "rectangle.split.3x1"
        case .splitSide: symbol = "rectangle.split.2x1"
        default: symbol = "rectangle.split.1x2"
        }
        layoutButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Toggle layout")

        flowTabs(animated: true)
    }

    override func layout() {
        super.layout()
        // Re-flow when the bar is resized enough to change what fits — a window
        // resize is continuous, so this pass doesn't animate. Height changes
        // (one row ↔ two) re-place too: row y-positions depend on it.
        if abs(tabsArea.bounds.width - lastFlowWidth) > 40 || tabsArea.bounds.height != lastFlowHeight {
            flowTabs(animated: false)
        }
    }

    /// One thing the flow places on a row: a run of one group's tabs inside a
    /// folder cell, or one of the trailing buttons.
    private enum FlowItem {
        case folder(FolderSegment)
        case overflow
        case add
    }

    /// A group's tabs on one row. A group wider than a row spills across two;
    /// only its first segment wears the folder's label tab — the second is a
    /// bare cell, the same folder continued.
    private struct FolderSegment {
        let groupKey: String
        let label: String
        let colorIndex: Int
        let tabs: [SessionTabInfo]
        let ordinal: Int
        var poolKey: String { "\(groupKey)#\(ordinal)" }
    }

    /// A folder's tint is **locked for as long as the folder is open** (owner
    /// call 2026-09-08): a new folder takes the lowest free accent and never
    /// recolors a neighbor; a closed folder frees its accent. Dragging can't
    /// change it either. Main (any root outside the worktree base) is plain.
    /// Beyond the palette's count, accents repeat.
    private var tintIndex: [String: Int] = [:]

    private func refreshTintIndex() {
        let open = Set(tabs.map(\.groupKey).filter {
            $0.hasPrefix(WorktreeManager.base + "/") || $0.hasPrefix("ssh://")
        })
        tintIndex = tintIndex.filter { open.contains($0.key) }
        // Newcomers in strip order, each taking the lowest accent not in use.
        for key in tabs.map(\.groupKey) where open.contains(key) && tintIndex[key] == nil {
            let used = Set(tintIndex.values)
            let free = (1...Theme.Folder.tintCount).first { !used.contains($0) }
            tintIndex[key] = free ?? (tintIndex.count % Theme.Folder.tintCount) + 1
        }
    }

    private func colorIndex(for groupKey: String) -> Int { tintIndex[groupKey] ?? 0 }

    private func tabWidth(_ info: SessionTabInfo) -> CGFloat {
        SessionTabView.desiredWidth(for: info, isActive: info.index == activeIndex)
    }

    /// A folder cell hugs its tabs — but never narrower than its own label
    /// tab, so a one-tab folder still says its whole name.
    private func segmentWidth(_ tabs: [SessionTabInfo]) -> CGFloat {
        let tabsWidth = Self.folderPadX * 2
            + tabs.reduce(0) { $0 + tabWidth($1) }
            + Self.tabGap * CGFloat(max(0, tabs.count - 1))
        let labelWidth = tabs.first.map { FolderView.labelWidth(for: $0.groupLabel) } ?? 0
        return max(tabsWidth, labelWidth + Theme.Elevation.radiusSmall * 2)
    }

    private func itemWidth(_ item: FlowItem) -> CGFloat {
        switch item {
        case .folder(let segment): return segmentWidth(segment.tabs)
        case .overflow, .add: return 26
        }
    }

    /// Spacing before `item` given what precedes it on the row: folders keep
    /// a clear gap between them; buttons tuck in closer.
    private func gap(after previous: FlowItem?, before item: FlowItem) -> CGFloat {
        guard let previous else { return 0 }
        if case .folder = previous, case .folder = item { return Self.folderGap }
        return Self.buttonGap
    }

    /// Lay tabs into one or two rows of folders, never splitting a group
    /// across rows unless the group alone exceeds a full row. Beyond two rows,
    /// the remainder collapses into a `»` menu — the bar must not grow into a
    /// third pane.
    ///
    /// Tab and folder views are reused by identity: frame changes glide
    /// (~200 ms) when `animated`, so a title rewrite slides neighbors instead
    /// of snapping them (MILESTONE_1 §12 risk 2, retired here).
    private func flowTabs(animated: Bool) {
        lastFlowWidth = tabsArea.bounds.width
        lastFlowHeight = tabsArea.bounds.height
        let rowWidth = max(240, tabsArea.bounds.width)

        // Group chunks: runs of consecutive tabs sharing a root.
        var chunks: [[SessionTabInfo]] = []
        for tab in tabs {
            if let last = chunks.last, last.first?.groupKey == tab.groupKey {
                chunks[chunks.count - 1].append(tab)
            } else {
                chunks.append([tab])
            }
        }

        // Folder chrome earns its place by separating groups: one group draws
        // bare tabs (owner call 2026-09-08).
        foldersVisible = chunks.count > 1
        refreshTintIndex()

        // Pack, reserving room on the last row for the `+` — and, if anything
        // overflowed, for the `»` too (a second pass with the wider reserve).
        var packed = pack(chunks: chunks, rowWidth: rowWidth, reserve: 26 + Self.buttonGap)
        if !packed.overflow.isEmpty {
            packed = pack(chunks: chunks, rowWidth: rowWidth, reserve: (26 + Self.buttonGap) * 2)
        }
        var rows = packed.rows
        let overflow = packed.overflow

        if overflow.isEmpty {
            overflowButton.isHidden = true
        } else {
            overflowButton.isHidden = false
            overflowButton.menu = overflowMenu(for: overflow)
            overflowButton.action = #selector(overflowTapped)
            // The `»` itself wears the loudest overflowed state (§7.1): peach
            // for a block, green for an unseen completion, else muted. Still —
            // no motion, no escalation.
            if overflow.contains(where: { $0.attention == .needsInput }) {
                overflowButton.contentTintColor = Theme.accentPeach
            } else if overflow.contains(where: { $0.attention == .doneUnseen }) {
                overflowButton.contentTintColor = Theme.accentGreen
            } else {
                overflowButton.contentTintColor = Theme.chromeMutedText
            }
            rows[rows.count - 1].append(.overflow)
        }
        rows[rows.count - 1].append(.add)

        place(rows: rows, animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        let newHeight = rows.count > 1 ? Self.twoRowHeight : Self.rowHeight
        if newHeight != desiredHeight {
            desiredHeight = newHeight
            backdropHeight?.constant = newHeight
            onDesiredHeightChange?(newHeight)
        }
    }

    /// The packing itself: whole groups jump to a fresh row rather than split;
    /// a group too wide for any row fills the row it's on and continues below;
    /// what no row can hold overflows. `reserve` keeps the last row's trailing
    /// buttons from being squeezed out.
    private func pack(chunks: [[SessionTabInfo]], rowWidth: CGFloat, reserve: CGFloat)
        -> (rows: [[FlowItem]], overflow: [SessionTabInfo]) {
        var rows: [[FlowItem]] = [[]]
        var widths: [CGFloat] = [0]
        var overflow: [SessionTabInfo] = []

        func limit() -> CGFloat { rows.count == 2 ? rowWidth - reserve : rowWidth }
        func fits(_ width: CGFloat) -> Bool {
            let lead: CGFloat = rows[rows.count - 1].isEmpty ? 0 : Self.folderGap
            return widths[rows.count - 1] + lead + width <= limit()
        }
        func newRow() -> Bool {
            guard rows.count < 2 else { return false }
            rows.append([])
            widths.append(0)
            return true
        }
        func append(_ segment: FolderSegment) {
            let lead: CGFloat = rows[rows.count - 1].isEmpty ? 0 : Self.folderGap
            rows[rows.count - 1].append(.folder(segment))
            widths[widths.count - 1] += lead + segmentWidth(segment.tabs)
        }

        outer: for (chunkIndex, chunk) in chunks.enumerated() {
            let key = chunk[0].groupKey
            let label = chunk[0].groupLabel
            // Keep the whole group on one row when a fresh row would hold it.
            if !rows[rows.count - 1].isEmpty, !fits(segmentWidth(chunk)), segmentWidth(chunk) <= limit() {
                _ = newRow()
            }
            var pending = chunk[...]
            var ordinal = 0
            while !pending.isEmpty {
                var take: [SessionTabInfo] = []
                for tab in pending {
                    if fits(segmentWidth(take + [tab])) { take.append(tab) } else { break }
                }
                if take.isEmpty {
                    if rows[rows.count - 1].isEmpty {
                        // A single tab wider than the row still gets placed —
                        // overhang beats an unreachable session.
                        take.append(pending[pending.startIndex])
                    } else if newRow() {
                        continue
                    } else {
                        overflow.append(contentsOf: pending)
                        for rest in chunks[(chunkIndex + 1)...] { overflow.append(contentsOf: rest) }
                        break outer
                    }
                }
                append(FolderSegment(groupKey: key, label: label, colorIndex: chunkIndex, tabs: take, ordinal: ordinal))
                ordinal += 1
                pending = pending.dropFirst(take.count)
                if !pending.isEmpty, !newRow() {
                    overflow.append(contentsOf: pending)
                    for rest in chunks[(chunkIndex + 1)...] { overflow.append(contentsOf: rest) }
                    break outer
                }
            }
        }
        // The reserve only bites on the last row; a one-row strip must honor it too.
        if rows.count == 1, widths[0] + reserve > rowWidth, rows[0].count > 1 {
            // Spill the last folder to a second row rather than crowd the `+`.
            if case .folder(let last) = rows[0].removeLast() {
                rows.append([.folder(last)])
            }
        }
        return (rows, overflow)
    }

    /// Materialize the flow: persistent views move to their new frames (gliding
    /// when animated), departed tabs and folders fade out, arrivals appear in
    /// place.
    private func place(rows: [[FlowItem]], animated: Bool) {
        var seenTabs = Set<UUID>()
        var seenFolders = Set<String>()
        var placements: [(NSView, CGRect)] = []
        var arrivals: [NSView] = []

        // Cells stack from the bottom; the top row's label tabs rise past the
        // area (and the bar) — nothing here clips, by design.
        let backdropInner = desiredHeight - 1 // minus the top border
        let cellsHeight = Self.cellHeight * CGFloat(rows.count) + (Self.rowGap + Self.folderTabHeight) * CGFloat(rows.count - 1)
        let base = (backdropInner - cellsHeight) / 2

        for (rowIndex, row) in rows.enumerated() {
            let cellBottom = base + CGFloat(rows.count - 1 - rowIndex) * Self.rowPitch
            let tabY = cellBottom + Self.folderPadY
            var x: CGFloat = 0
            var previous: FlowItem?
            for item in row {
                x += gap(after: previous, before: item)
                let width = itemWidth(item)
                switch item {
                case .folder(let segment) where !foldersVisible:
                    // Bare tabs: no cell, no label; same geometry so a second
                    // group arriving only fades folders in around them.
                    var tabX = x + Self.folderPadX
                    for info in segment.tabs {
                        seenTabs.insert(info.id)
                        let view: SessionTabView
                        if let existing = tabViews[info.id] {
                            view = existing
                        } else {
                            view = SessionTabView(sessionId: info.id)
                            wire(view)
                            tabViews[info.id] = view
                            tabsArea.addSubview(view)
                            arrivals.append(view)
                        }
                        view.apply(info: info, isActive: info.index == activeIndex)
                        let tabW = tabWidth(info)
                        if drag?.id != info.id {
                            placements.append((view, CGRect(x: tabX, y: tabY, width: tabW, height: Self.tabHeight)))
                        }
                        tabX += tabW + Self.tabGap
                    }
                case .folder(let segment):
                    seenFolders.insert(segment.poolKey)
                    let folder: FolderView
                    if let existing = folderViews[segment.poolKey] {
                        folder = existing
                    } else {
                        folder = FolderView()
                        folder.onDragBegan = { [weak self] view, event in self?.folderDragBegan(view, event) }
                        folder.onDragMoved = { [weak self] view, event in self?.folderDragMoved(view, event) }
                        folder.onDragEnded = { [weak self] view in self?.folderDragEnded(view) }
                        let key = segment.groupKey
                        folder.branchProvider = key.hasPrefix("ssh://") ? nil : { WorktreeManager.currentBranch(key) }
                        folderViews[segment.poolKey] = folder
                        // Below every tab — folders are the ground the tabs sit on.
                        tabsArea.addSubview(folder, positioned: .below, relativeTo: nil)
                        arrivals.append(folder)
                    }
                    let removable = segment.groupKey.hasPrefix(WorktreeManager.base + "/")
                    folder.groupKey = segment.groupKey
                    folder.apply(
                        label: segment.ordinal == 0 ? segment.label : nil,
                        fill: Theme.Folder.fill(colorIndex(for: segment.groupKey)),
                        coat: Theme.Folder.labelCoat(colorIndex(for: segment.groupKey)),
                        onRemove: removable ? { [weak self] in
                            self?.delegate?.bottomBarDidRequestRemoveWorktree(at: segment.groupKey)
                        } : nil
                    )
                    let folderDragged = groupDrag?.key == segment.groupKey
                    if !folderDragged {
                        placements.append((folder, CGRect(
                            x: x, y: cellBottom, width: width, height: Self.cellHeight + Self.folderTabHeight
                        )))
                    }
                    var tabX = x + Self.folderPadX
                    for info in segment.tabs {
                        seenTabs.insert(info.id)
                        let view: SessionTabView
                        if let existing = tabViews[info.id] {
                            view = existing
                        } else {
                            view = SessionTabView(sessionId: info.id)
                            wire(view)
                            tabViews[info.id] = view
                            tabsArea.addSubview(view)
                            arrivals.append(view)
                        }
                        view.apply(info: info, isActive: info.index == activeIndex)
                        let tabW = tabWidth(info)
                        // The tab under the pointer follows the pointer, not the flow.
                        if drag?.id != info.id, !folderDragged {
                            placements.append((view, CGRect(x: tabX, y: tabY, width: tabW, height: Self.tabHeight)))
                        }
                        tabX += tabW + Self.tabGap
                    }
                case .overflow:
                    placements.append((overflowButton, CGRect(x: x + 2, y: tabY, width: 22, height: Self.tabHeight)))
                case .add:
                    placements.append((addButton, CGRect(x: x + 2, y: tabY, width: 22, height: Self.tabHeight)))
                }
                x += width
                previous = item
            }
        }

        // Departed tabs (closed, or pushed into the overflow menu) and folders.
        var departed: [NSView] = []
        for (id, view) in tabViews where !seenTabs.contains(id) {
            tabViews[id] = nil
            departed.append(view)
        }
        for (key, view) in folderViews where !seenFolders.contains(key) {
            folderViews[key] = nil
            departed.append(view)
        }
        for view in departed {
            if animated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    view.animator().alphaValue = 0
                }, completionHandler: { view.removeFromSuperview() })
            } else {
                view.removeFromSuperview()
            }
        }

        let apply = {
            for (view, frame) in placements {
                // New arrivals appear in place — only *moves* glide.
                if arrivals.contains(where: { $0 === view }) {
                    view.frame = frame
                } else if animated {
                    view.animator().frame = frame
                } else {
                    view.frame = frame
                }
                view.isHidden = false
            }
        }
        let stagger = !hasRevealed && arrivals.count > 1
        if !placements.isEmpty { hasRevealed = true }

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                apply()
            }
            // Restore stagger (§5): once per launch, tabs fade-and-settle
            // left-to-right, ~40 ms apart, sub-300 ms total. Never again.
            for (index, view) in arrivals.enumerated() {
                view.alphaValue = 0
                let settle = {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = 0.2
                        ctx.allowsImplicitAnimation = true
                        view.animator().alphaValue = 1
                    }
                }
                if stagger, index > 0 {
                    let delay = min(Double(index) * 0.04, 0.1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: settle)
                } else {
                    settle()
                }
            }
        } else {
            apply()
        }
    }

    private func wire(_ view: SessionTabView) {
        view.onSelect = { [weak self] idx in self?.delegate?.bottomBarDidSelectSession(at: idx) }
        view.onClose = { [weak self] idx in self?.delegate?.bottomBarDidRequestCloseSession(at: idx) }
        view.onRenameCommit = { [weak self] idx, title in self?.delegate?.bottomBarDidRenameSession(at: idx, title: title) }
        view.onRenameEnd = { [weak self] in self?.renameDidEnd() }
        view.onDragBegan = { [weak self] tab, event in self?.dragBegan(tab, event) }
        view.onDragMoved = { [weak self] tab, event in self?.dragMoved(tab, event) }
        view.onDragEnded = { [weak self] tab in self?.dragEnded(tab) }
    }

    // MARK: Drag to reorder (MILESTONE_1 §7, 2026-09-07)

    /// The tab under the pointer: it rides the pointer while the rest of the
    /// strip re-flows live around the order it proposes.
    private var drag: (id: UUID, grabOffset: CGFloat)?

    private func dragBegan(_ tab: SessionTabView, _ event: NSEvent) {
        let point = tabsArea.convert(event.locationInWindow, from: nil)
        drag = (tab.sessionId, point.x - tab.frame.minX)
        // Above everything else in the strip while it travels.
        tabsArea.addSubview(tab)
        tab.wantsLayer = true
        tab.shadow = Theme.Elevation.raisedShadow
    }

    private func dragMoved(_ tab: SessionTabView, _ event: NSEvent) {
        guard let drag, drag.id == tab.sessionId else { return }
        let point = tabsArea.convert(event.locationInWindow, from: nil)
        let x = min(max(point.x - drag.grabOffset, -tab.frame.width / 2), tabsArea.bounds.width - tab.frame.width / 2)
        tab.frame.origin.x = x
        let proposed = proposeOrder(dragging: drag.id, frame: tab.frame)
        if proposed.map(\.id) != tabs.map(\.id) {
            tabs = proposed
            flowTabs(animated: true)
        }
    }

    private func dragEnded(_ tab: SessionTabView) {
        guard drag?.id == tab.sessionId else { return }
        drag = nil
        tab.shadow = nil
        delegate?.bottomBarDidReorderSessions(order: tabs.map(\.id))
        flowTabs(animated: true)
    }

    /// A folder dragged by its label tab: the whole group — cell and tabs —
    /// rides the pointer, and swaps with a neighbor folder once its center
    /// crosses the neighbor's.
    private var groupDrag: (key: String, grabOffset: CGFloat)?

    private func folderDragBegan(_ folder: FolderView, _ event: NSEvent) {
        guard let key = folder.groupKey else { return }
        let point = tabsArea.convert(event.locationInWindow, from: nil)
        groupDrag = (key, point.x - folder.frame.minX)
        // Lift the folder and its tabs above the rest of the strip.
        tabsArea.addSubview(folder)
        for info in tabs where info.groupKey == key { if let view = tabViews[info.id] { tabsArea.addSubview(view) } }
        folder.shadow = Theme.Elevation.raisedShadow
        NSCursor.closedHand.push()
    }

    private func folderDragMoved(_ folder: FolderView, _ event: NSEvent) {
        guard let groupDrag, groupDrag.key == folder.groupKey else { return }
        let point = tabsArea.convert(event.locationInWindow, from: nil)
        let x = min(max(point.x - groupDrag.grabOffset, -folder.frame.width / 2), tabsArea.bounds.width - folder.frame.width / 2)
        let dx = x - folder.frame.minX
        folder.frame.origin.x = x
        for info in tabs where info.groupKey == groupDrag.key { tabViews[info.id]?.frame.origin.x += dx }
        let cell = CGRect(x: folder.frame.minX, y: folder.frame.minY, width: folder.frame.width, height: Self.cellHeight)
        let proposed = proposeGroupOrder(dragging: groupDrag.key, frame: cell)
        if proposed.map(\.id) != tabs.map(\.id) {
            tabs = proposed
            flowTabs(animated: true)
        }
    }

    private func folderDragEnded(_ folder: FolderView) {
        guard groupDrag?.key == folder.groupKey else { return }
        groupDrag = nil
        folder.shadow = nil
        NSCursor.pop()
        delegate?.bottomBarDidReorderSessions(order: tabs.map(\.id))
        flowTabs(animated: true)
    }

    private func proposeGroupOrder(dragging key: String, frame: CGRect) -> [SessionTabInfo] {
        var chunks: [[SessionTabInfo]] = []
        for tab in tabs {
            if let last = chunks.last, last.first?.groupKey == tab.groupKey {
                chunks[chunks.count - 1].append(tab)
            } else {
                chunks.append([tab])
            }
        }
        guard let g = chunks.firstIndex(where: { $0.first?.groupKey == key }) else { return tabs }
        return (Self.swapNeighborFolder(chunks: chunks, at: g, dragged: frame, folderViews: folderViews) ?? chunks).flatMap { $0 }
    }

    /// How far past a neighbor's midpoint the dragged edge must travel before
    /// the two trade places — a little past halfway, so the swap reads as
    /// earned but never waits for a full pass.
    private static let swapOvershoot: CGFloat = 6

    /// The order the pointer is asking for. Within its folder the dragged tab
    /// trades places with a sibling once its *leading edge* is a little past
    /// the sibling's midpoint (owner call 2026-09-07). Pushed the same way
    /// into a neighboring folder, the two *folders* swap — a session never
    /// changes worktree by being dragged, so the group moves as one.
    private func proposeOrder(dragging id: UUID, frame dragged: CGRect) -> [SessionTabInfo] {
        var chunks: [[SessionTabInfo]] = []
        for tab in tabs {
            if let last = chunks.last, last.first?.groupKey == tab.groupKey {
                chunks[chunks.count - 1].append(tab)
            } else {
                chunks.append([tab])
            }
        }
        guard let g = chunks.firstIndex(where: { $0.contains { $0.id == id } }),
              let position = chunks[g].firstIndex(where: { $0.id == id }) else { return tabs }
        let rowTolerance = Self.cellHeight
        func sameRow(_ frame: CGRect) -> Bool { abs(frame.midY - dragged.midY) < rowTolerance }

        // Within the folder: one step at a time, against the immediate
        // neighbor on each side — the flow re-lays after every step.
        var chunk = chunks[g]
        if position > 0, let left = tabViews[chunk[position - 1].id]?.frame, sameRow(left),
           dragged.minX < left.midX - Self.swapOvershoot {
            chunk.swapAt(position - 1, position)
        } else if position + 1 < chunk.count, let right = tabViews[chunk[position + 1].id]?.frame, sameRow(right),
                  dragged.maxX > right.midX + Self.swapOvershoot {
            chunk.swapAt(position, position + 1)
        }
        chunks[g] = chunk

        if let swapped = Self.swapNeighborFolder(chunks: chunks, at: g, dragged: dragged, folderViews: folderViews) {
            chunks = swapped
        }
        return chunks.flatMap { $0 }
    }

    /// Shared by both drags: swap folder `g` with the neighbor whose midpoint
    /// the dragged edge has passed (by `swapOvershoot`), same row only.
    private static func swapNeighborFolder(
        chunks: [[SessionTabInfo]], at g: Int, dragged: CGRect, folderViews: [String: FolderView]
    ) -> [[SessionTabInfo]]? {
        func cell(of chunk: [SessionTabInfo]) -> CGRect? {
            guard let key = chunk.first?.groupKey, let frame = folderViews["\(key)#0"]?.frame else { return nil }
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: cellHeight)
        }
        var chunks = chunks
        if g > 0, let left = cell(of: chunks[g - 1]), abs(left.midY - dragged.midY) < cellHeight,
           dragged.minX < left.midX - swapOvershoot {
            chunks.swapAt(g - 1, g)
            return chunks
        }
        if g + 1 < chunks.count, let right = cell(of: chunks[g + 1]), abs(right.midY - dragged.midY) < cellHeight,
           dragged.maxX > right.midX + swapOvershoot {
            chunks.swapAt(g, g + 1)
            return chunks
        }
        return nil
    }

    /// Start the inline rename on a session's tab (double-click does this
    /// directly; the palette's "Session: Rename…" routes here).
    func beginRename(at index: Int) {
        guard let view = tabViews.values.first(where: { $0.index == index }) else { return }
        view.beginRename()
    }

    /// Fired after an inline rename ends however it ends — the owner restores
    /// keyboard focus to the session.
    var onRenameDidEnd: (() -> Void)?
    private func renameDidEnd() { onRenameDidEnd?() }

    /// §7.1 — the agent's exact state, always visible: overflowed tabs keep
    /// their ⎇ and attention marks inside the `»` menu.
    private func overflowMenu(for tabs: [SessionTabInfo]) -> NSMenu {
        let menu = NSMenu()
        for tab in tabs {
            // No folder in a menu: the ⎇ mark comes back on the row itself.
            let title = (tab.isWorktree ? "⎇ " : "") + SessionTabView.label(for: tab)
            let item = NSMenuItem(title: title, action: #selector(overflowItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tab.index
            item.image = Self.menuBadgeImage(for: tab.attention)
            menu.addItem(item)
        }
        return menu
    }

    /// The tab badges, translated to menu-item images: the same 6 pt dot, the
    /// same inanimate peach `!`. `none` gets a clear placeholder so titles
    /// align whether or not a session has state.
    private static func menuBadgeImage(for attention: Session.Attention) -> NSImage {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            switch attention {
            case .none:
                break
            case .needsInput:
                let mark = NSAttributedString(string: "!", attributes: [
                    .font: Theme.Typography.ui(Theme.Typography.small, weight: .heavy),
                    .foregroundColor: Theme.accentPeach,
                ])
                let markSize = mark.size()
                mark.draw(at: NSPoint(x: (rect.width - markSize.width) / 2, y: (rect.height - markSize.height) / 2))
            case .working, .waiting, .doneUnseen:
                let color: NSColor
                switch attention {
                case .working: color = Theme.accentBlue
                case .doneUnseen: color = Theme.accentGreen
                default: color = Theme.accentPeach
                }
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Clock

    private func startClock() {
        tickClock()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tickClock() }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func tickClock() {
        let now = Date()
        clockPrefixLabel.stringValue = DateFormatter.cached("HH").string(from: now)
        clockSuffixLabel.stringValue = DateFormatter.cached("mm").string(from: now)
            + " · " + DateFormatter.cached("MMM dd").string(from: now)
    }

    // MARK: Actions

    @objc private func addTapped() { delegate?.bottomBarDidRequestNewSession() }
    @objc private func layoutTapped() { delegate?.bottomBarDidToggleLayout() }
    @objc private func settingsTapped() { delegate?.bottomBarDidRequestSettings() }
    @objc private func overflowTapped() {
        overflowButton.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowButton.bounds.maxY), in: overflowButton)
    }
    @objc private func overflowItemSelected(_ sender: NSMenuItem) {
        delegate?.bottomBarDidSelectSession(at: sender.tag)
    }
}

/// A single session tab: optional attention badge, ellipsized title. The
/// active tab — and only the active tab — carries a close `×` at its trailing
/// edge: the tab you can close is the one you're looking at, and inactive
/// tabs stay quiet. Click
/// selects; double-click renames **in place** — the title becomes an editable
/// field under the cursor (Finder's gesture), `↩` commits, `Esc` cancels,
/// empty reverts to the live auto title. Persistent across bar updates so its
/// state changes can animate:
/// attention cross-fades (~250 ms), a green arrival does one soft scale-in,
/// the working blue carries the ~4 s subliminal pulse, and the peach `!`
/// **never** animates — urgency reads as stillness (§1.3).
private final class SessionTabView: NSView, NSTextFieldDelegate {
    let sessionId: UUID
    private(set) var index: Int = -1
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRenameCommit: ((Int, String?) -> Void)?
    var onRenameEnd: (() -> Void)?
    var onDragBegan: ((SessionTabView, NSEvent) -> Void)?
    var onDragMoved: ((SessionTabView, NSEvent) -> Void)?
    var onDragEnded: ((SessionTabView) -> Void)?
    private var pressLocation: CGPoint?
    private var isDragging = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = HoverFadeButton()
    private var badgeView: NSView?
    private var attention: Session.Attention = .none
    private var attentionSince: Date?
    private var isActive = false
    private var applied = false
    private var toolTipRect: CGRect = .null
    /// The unadorned display title (no ⎇), for seeding the rename field.
    private var rawTitle = ""
    private var editField: NSTextField?
    private var renameCancelled = false

    override var mouseDownCanMoveWindow: Bool { false }

    init(sessionId: UUID) {
        self.sessionId = sessionId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusSmall

        // No usesSingleLineMode: its cell centers glyphs on different metrics
        // than a plain label, which is exactly the "text sits low in the tab"
        // read next to the constraint-centered pill (owner call 2026-07-13).
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close session")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .medium)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        closeButton.alphaValue = HoverFadeButton.restingAlpha
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Estimated width for the flow: full label + glyphs + padding, plus the
    /// leading close `×` on the active tab. Titles are uncapped — the two-row
    /// wrap and the `»` overflow absorb long ones.
    static func desiredWidth(for info: SessionTabInfo, isActive: Bool) -> CGFloat {
        // Measure at the active (semibold) weight — a hair wider than regular
        // at this size, and the estimate must never come in under the truth.
        let font = Theme.Typography.mono(Theme.Typography.body, weight: .semibold)
        let textWidth = (label(for: info) as NSString).size(withAttributes: [.font: font]).width
        let badge: CGFloat = info.attention == .none ? 0 : 11
        // +4: NSTextFieldCell pads 2pt each side beyond the glyph width.
        return ceil(textWidth) + badge + 8 + (isActive ? closeSlot : 8) + 4
    }

    /// The `×` sits close: 3pt off the title, 4pt off the edge (owner call
    /// 2026-09-10 — the old 8/6 read as dead space).
    static let closeMargin: CGFloat = 4
    static let closeGap: CGFloat = 0   // the 12pt box already insets its 8pt glyph
    static let closeSlot: CGFloat = closeGap + 12 + closeMargin

    /// The tab's label: the title, then the `@host` mark for remote sessions —
    /// dropped when the title *is* the host ("jarvis @jarvis" says it once).
    /// The worktree mark moved to the folder the tab sits in (2026-09-03);
    /// only the `»` menu, which has no folder, puts ⎇ back. (Index numbering
    /// was tried and dropped — the tmux reference was about presentation, not
    /// anatomy; owner call 2026-07-13.)
    static func label(for info: SessionTabInfo) -> String {
        let title = info.title.isEmpty ? "untitled" : info.title
        let host = info.remoteHost.flatMap { $0 == info.title ? nil : " @\($0)" } ?? ""
        return title + host
    }

    func apply(info: SessionTabInfo, isActive: Bool) {
        index = info.index
        rawTitle = info.title
        let text = Self.label(for: info)
        if titleLabel.stringValue != text { titleLabel.stringValue = text }

        if self.isActive != isActive || !applied {
            self.isActive = isActive
            // Active tab wears the tmux green; inactive tabs stay quiet.
            layer?.backgroundColor = (isActive ? Theme.accentGreen : .clear).cgColor
            titleLabel.font = Theme.Typography.mono(Theme.Typography.body, weight: isActive ? .semibold : .regular)
            // Inactive titles at subtext0 (the §1.2 cap), not overlay0: over a
            // folder fill, overlay0 fell below legible (owner call 2026-09-08).
            titleLabel.textColor = isActive ? Theme.accentTextDark : Theme.chromeText
            closeButton.contentTintColor = Theme.accentTextDark
            closeButton.isHidden = !isActive
            // Invisible until the pointer is over the tab (owner call
            // 2026-07-13); the slot stays reserved so nothing shifts on hover.
            closeButton.alphaValue = 0
        }
        attentionSince = info.attentionSince
        setAttention(info.attention, animated: applied)
        applied = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // The close `×` sits at the trailing edge (owner call 2026-09-08); its
        // slot is reserved by activeness, not visibility, so the hover reveal
        // never shifts text.
        let closeWidth: CGFloat = 12
        let leading: CGFloat = 8
        let trailingSlot: CGFloat = isActive ? Self.closeSlot : 8
        let hasBadge = badgeView != nil
        if !closeButton.isHidden {
            // Hug the title's real end, not the tab's edge: the width estimate
            // carries a few points of slack, and that slack belongs outside
            // the ×, not between it and the text (owner call 2026-09-10).
            let titleEnd = leading + (hasBadge ? 11 : 0) + ceil(titleLabel.fittingSize.width)
            let x = min(titleEnd + Self.closeGap, bounds.width - Self.closeMargin - closeWidth)
            closeButton.frame = CGRect(
                x: x,
                y: (bounds.height - closeWidth) / 2,
                width: closeWidth,
                height: closeWidth
            )
        }
        if let badge = badgeView {
            let size = badge.frame.size == .zero ? badge.fittingSize : badge.frame.size
            badge.frame = CGRect(
                x: leading,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        // Elapsed time on inquiry (§4): hovering the dot answers the one
        // question it can't show; the string is computed at hover-time via the
        // owner callback so it's never stale. Rebuild the tip region only when
        // it moves — layout() runs every bar refresh, and tearing the tip down
        // each pass perpetually resets the hover timer (it would never show).
        let tipRect = badgeView.map { $0.frame.insetBy(dx: -4, dy: -4) } ?? .null
        if tipRect != toolTipRect {
            toolTipRect = tipRect
            removeAllToolTips()
            if !tipRect.isNull {
                addToolTip(tipRect, owner: self, userData: nil)
            }
        }
        let titleX: CGFloat = leading + (hasBadge ? 11 : 0)
        let titleHeight = titleLabel.fittingSize.height
        titleLabel.frame = CGRect(
            x: titleX,
            y: round((bounds.height - titleHeight) / 2),
            width: max(0, bounds.width - titleX - trailingSlot),
            height: titleHeight
        )
        editField?.frame = editFieldFrame()
    }

    // MARK: Inline rename

    private func editFieldFrame() -> CGRect {
        CGRect(
            x: titleLabel.frame.minX - 2,
            y: (bounds.height - 16) / 2,
            width: max(40, bounds.width - titleLabel.frame.minX - 6),
            height: 16
        )
    }

    /// Swap the title for an editable field in place. Select-all seeded with
    /// the current name, like Finder; `↩`/click-away commits, `Esc` cancels.
    func beginRename() {
        guard editField == nil else { return }
        let field = NSTextField(string: rawTitle)
        field.font = Theme.Typography.mono(Theme.Typography.body, weight: isActive ? .semibold : .regular)
        field.textColor = isActive ? Theme.accentTextDark : Theme.chromeText
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.delegate = self
        addSubview(field)
        field.frame = editFieldFrame()
        titleLabel.isHidden = true
        editField = field
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    private func endRename() {
        guard let field = editField else { return }
        editField = nil
        field.removeFromSuperview()
        titleLabel.isHidden = false
        onRenameEnd?()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = editField else { return }
        if !renameCancelled {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            onRenameCommit?(index, text.isEmpty ? nil : text)
        }
        renameCancelled = false
        endRename()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            renameCancelled = true
            window?.makeFirstResponder(nil) // resigns the editor → didEndEditing
            return true
        }
        return false
    }

    // MARK: Attention badge (MILESTONE_1 §7.1 + POLISH_PLAN §3)

    /// No escalation (§1.3, rule standing): states swap by ~250 ms cross-fade;
    /// the only other motions are the green arrival's single scale-in and the
    /// working blue's subliminal pulse. Nothing here ever raises its voice
    /// with age, and the peach `!` is deliberately inanimate.
    private func setAttention(_ newAttention: Session.Attention, animated: Bool) {
        guard newAttention != attention || !applied else { return }
        attention = newAttention

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fade = animated && !reduceMotion

        if let old = badgeView {
            badgeView = nil
            if fade {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    old.animator().alphaValue = 0
                }, completionHandler: { old.removeFromSuperview() })
            } else {
                old.removeFromSuperview()
            }
        }

        guard newAttention != .none else { return }
        let badge = Self.makeBadge(for: newAttention)
        addSubview(badge)
        badgeView = badge
        layout()

        if fade {
            badge.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                badge.animator().alphaValue = 1
            }
        }
        guard !reduceMotion else { return }

        switch newAttention {
        case .doneUnseen:
            // One soft scale-in (1.0 → 1.3 → 1.0), then stillness.
            if let dot = (badge as? BadgeDotView)?.dotLayer {
                let arrival = CAKeyframeAnimation(keyPath: "transform.scale")
                arrival.values = [1.0, 1.3, 1.0]
                arrival.keyTimes = [0, 0.5, 1]
                arrival.duration = 0.3
                arrival.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dot.add(arrival, forKey: "arrival")
            }
        case .working:
            // The ~4 s subliminal pulse (§1.1 item 4): ±10% opacity, forever.
            if let dot = (badge as? BadgeDotView)?.dotLayer {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.8
                pulse.duration = 2.0
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                dot.add(pulse, forKey: "workingPulse")
            }
        case .waiting, .needsInput, .none:
            break // still — the peach states never animate (§1.3)
        }
    }

    private static func makeBadge(for attention: Session.Attention) -> NSView {
        if attention == .needsInput {
            let mark = NSTextField(labelWithString: "!")
            mark.font = Theme.Typography.ui(Theme.Typography.small, weight: .heavy)
            mark.textColor = Theme.accentPeach
            mark.sizeToFit()
            return mark
        }
        let color: NSColor
        switch attention {
        case .working: color = Theme.accentBlue
        case .doneUnseen: color = Theme.accentGreen
        default: color = Theme.accentPeach
        }
        return BadgeDotView(color: color)
    }

    override func mouseDown(with event: NSEvent) {
        guard editField == nil else { return } // clicks during a rename belong to the editor
        if event.clickCount == 2 {
            beginRename()
        } else {
            onSelect?(index)
            pressLocation = event.locationInWindow
            isDragging = false
        }
    }

    /// A few points of travel turns the press into a drag (MILESTONE_1 §7):
    /// the tab follows the pointer; the strip re-flows around it.
    override func mouseDragged(with event: NSEvent) {
        guard editField == nil, let press = pressLocation else { return }
        if !isDragging {
            guard hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) > 4 else { return }
            isDragging = true
            onDragBegan?(self, event)
        }
        onDragMoved?(self, event)
    }

    override func mouseUp(with event: NSEvent) {
        pressLocation = nil
        if isDragging {
            isDragging = false
            onDragEnded?(self)
        }
    }

    // The close `×` reveals on tab hover (its own HoverFadeButton tracking
    // then takes it to full strength under the pointer).
    private var tabTracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tabTracking { removeTrackingArea(tabTracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tabTracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        if !closeButton.isHidden { closeButton.alphaValue = HoverFadeButton.restingAlpha }
    }

    override func mouseExited(with event: NSEvent) {
        closeButton.alphaValue = 0
    }

    @objc private func closeTapped() { onClose?(index) }

    /// One muted line — `working · 4m` — computed when asked, never shown
    /// unasked (§1.3). NSToolTipOwner callback (informal protocol, not an
    /// override).
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        let word: String
        switch attention {
        case .working: word = "working"
        case .waiting: word = "waiting"
        case .needsInput: word = "blocked"
        case .doneUnseen: word = "done"
        case .none: return ""
        }
        guard let since = attentionSince else { return word }
        let seconds = max(0, Int(Date().timeIntervalSince(since)))
        let elapsed: String
        switch seconds {
        case ..<60: elapsed = "\(seconds)s"
        case ..<3600: elapsed = "\(seconds / 60)m"
        default: elapsed = "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
        return "\(word) · \(elapsed)"
    }
}

/// The active tab's close `×`: quiet at rest, full-strength under the pointer.
/// Opacity only — no color change, no growth, no motion (§1.3).
/// The tab strip's manual-layout host. Its children may overhang it (folder
/// label tabs), so it can hit-test them without the frame check.
private final class TabsAreaView: NSView {
    /// `point` in this view's own coordinates.
    func hitTest(_ point: NSPoint, outsideFrame: Bool) -> NSView? {
        for sub in subviews.reversed() where !sub.isHidden {
            if let hit = sub.hitTest(point) { return hit }
        }
        return nil
    }
}

/// One worktree folder in the strip: a rounded cell that holds a group's tabs,
/// with a label tab rising from its top-left edge — past the bar's top, over
/// the pane content — drawn as one continuous path so it reads as a folder,
/// not a box wearing a badge. A
/// continuation segment (a group split across rows) has no label tab.
/// Right-click on the label offers to remove the worktree when it is one.
private final class FolderView: NSView {
    private static let radius: CGFloat = Theme.Elevation.radiusSmall
    private static let tabHeight: CGFloat = 13
    private var label: String?
    private var fill: NSColor = .clear
    private var coat: NSColor = .clear
    private var onRemove: (() -> Void)?
    var groupKey: String?
    /// Resolves the branch checked out in this folder's worktree, on inquiry.
    var branchProvider: (() -> String?)?
    private var hoverTimer: Timer?
    private var reveal: BranchRevealView?
    private var labelTracking: NSTrackingArea?
    var onDragBegan: ((FolderView, NSEvent) -> Void)?
    var onDragMoved: ((FolderView, NSEvent) -> Void)?
    var onDragEnded: ((FolderView) -> Void)?
    private var pressLocation: CGPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    /// The label tab's hit region — the folder's handle.
    private var labelRect: CGRect {
        guard label != nil else { return .null }
        return CGRect(x: 0, y: bounds.height - Self.tabHeight, width: labelTabWidth(), height: Self.tabHeight)
    }

    /// The handle promises a drag, so it wears the hand (the session tabs,
    /// whose first act is select, don't).
    override func resetCursorRects() {
        let rect = labelRect
        if !rect.isNull { addCursorRect(rect, cursor: .openHand) }
    }

    // MARK: Branch on inquiry (§1.3)

    /// Resting on the label for a beat reveals the branch checked out there —
    /// a chip floating *above* the label, over the pane content the label
    /// already rises into. Nothing in the strip moves; it's gone on exit.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let labelTracking { removeTrackingArea(labelTracking) }
        let rect = labelRect
        guard !rect.isNull else { return }
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        labelTracking = area
    }

    /// The label rect depends on the frame, which lands after `apply` — so
    /// re-register on every geometry change, not just on content change.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseEntered(with event: NSEvent) {
        guard branchProvider != nil, !isDragging else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.showReveal()
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        hideReveal()
    }

    private func showReveal() {
        guard reveal == nil, let branch = branchProvider?(), let superview else { return }
        let chip = BranchRevealView(branch: branch, fill: coat)
        let size = chip.fittingSize
        // Anchored to the label's left edge, sitting on its top edge.
        let origin = convert(NSPoint(x: 0, y: bounds.height - 1), to: superview)
        chip.frame = NSRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
        chip.alphaValue = 0
        superview.addSubview(chip)
        reveal = chip
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            chip.animator().alphaValue = 1
        }
    }

    private func hideReveal() {
        guard let chip = reveal else { return }
        reveal = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            chip.animator().alphaValue = 0
        }, completionHandler: { chip.removeFromSuperview() })
    }

    /// Only the label tab is interactive; the cell behind the tabs is ground.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return labelRect.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        pressLocation = event.locationInWindow
        isDragging = false
        hoverTimer?.invalidate()
        hideReveal()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press = pressLocation else { return }
        if !isDragging {
            guard hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) > 4 else { return }
            isDragging = true
            onDragBegan?(self, event)
        }
        onDragMoved?(self, event)
    }

    override func mouseUp(with event: NSEvent) {
        pressLocation = nil
        if isDragging {
            isDragging = false
            onDragEnded?(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    func apply(label: String?, fill: NSColor, coat: NSColor, onRemove: (() -> Void)?) {
        self.onRemove = onRemove
        guard self.label != label || self.fill != fill || self.coat != coat else { return }
        self.label = label
        self.fill = fill
        self.coat = coat
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        updateTrackingAreas()
    }

    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: Theme.Typography.mono(Theme.Typography.small, weight: .medium),
        .foregroundColor: Theme.Folder.labelText,
    ]
    private var labelAttributes: [NSAttributedString.Key: Any] { Self.labelAttributes }

    /// Worktree labels arrive as `⎇ dir`; the glyph is drawn as a tree symbol
    /// (these are work*trees* — the branch glyph belongs to the branch chip).
    private static let treeMarker = "⎇ "
    private static let treeGlyphWidth: CGFloat = 13

    private static func split(_ label: String) -> (tree: Bool, text: String) {
        label.hasPrefix(treeMarker) ? (true, String(label.dropFirst(treeMarker.count))) : (false, label)
    }

    /// The tree, drawn: a conifer — three stacked tiers on a short trunk (the
    /// owner's pick 2026-09-08; reads at 10 pt where a canopy turns to a
    /// lollipop). One opaque fill; the trunk runs up into the lowest tier so
    /// there is never a seam between them. `rect` is the glyph box.
    private static func treePath(in rect: CGRect) -> NSBezierPath {
        let path = NSBezierPath()
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: rect.minX + x * w, y: rect.minY + y * h) }
        func tier(top: CGFloat, bottom: CGFloat, half: CGFloat) {
            let t = NSBezierPath()
            t.move(to: pt(0.5, top))
            t.line(to: pt(0.5 + half, bottom))
            t.line(to: pt(0.5 - half, bottom))
            t.close()
            path.append(t)
        }
        // Two tiers, not three: at 10 pt three collapsed into one blob (owner
        // call 2026-09-08). Narrow-ish top over a wide skirt, deep notch —
        // the step is the whole silhouette at this size.
        tier(top: 1.00, bottom: 0.50, half: 0.40)
        tier(top: 0.62, bottom: 0.20, half: 0.50)
        // The trunk winds the same way as the tiers (clockwise): under the
        // non-zero rule an opposite-wound overlap cancels to a hole — which
        // was the "gap between the log and the triangles".
        let trunk = NSBezierPath()
        trunk.move(to: pt(0.42, 0.32))
        trunk.line(to: pt(0.58, 0.32))
        trunk.line(to: pt(0.58, 0.0))
        trunk.line(to: pt(0.42, 0.0))
        trunk.close()
        path.append(trunk)
        return path
    }

    /// A label tab's natural width: text plus insets. The flow sizes cells by it.
    static func labelWidth(for label: String) -> CGFloat {
        let (tree, text) = split(label)
        return ceil((text as NSString).size(withAttributes: labelAttributes).width) + 14 + (tree ? treeGlyphWidth : 0)
    }

    /// The label tab's width: its text plus insets, never wider than the cell.
    private func labelTabWidth() -> CGFloat {
        guard let label else { return 0 }
        return min(Self.labelWidth(for: label), bounds.width - Self.radius * 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = Self.radius
        let width = bounds.width
        let cellTop = bounds.height - Self.tabHeight
        let path = NSBezierPath()
        if label != nil {
            let tabWidth = labelTabWidth()
            let top = bounds.height
            // Clockwise from the cell's bottom-left, around the cell, up the
            // label tab, and back down its left edge.
            path.move(to: NSPoint(x: r, y: 0))
            path.appendArc(from: NSPoint(x: width, y: 0), to: NSPoint(x: width, y: cellTop), radius: r)
            path.appendArc(from: NSPoint(x: width, y: cellTop), to: NSPoint(x: tabWidth, y: cellTop), radius: r)
            path.line(to: NSPoint(x: tabWidth, y: cellTop))
            path.appendArc(from: NSPoint(x: tabWidth, y: top), to: NSPoint(x: 0, y: top), radius: r)
            path.appendArc(from: NSPoint(x: 0, y: top), to: NSPoint(x: 0, y: 0), radius: r)
            path.appendArc(from: NSPoint(x: 0, y: 0), to: NSPoint(x: width, y: 0), radius: r)
            path.close()
        } else {
            path.appendRoundedRect(NSRect(x: 0, y: 0, width: width, height: cellTop), xRadius: r, yRadius: r)
        }
        fill.setFill()
        path.fill()

        if let label {
            let tabWidth = labelTabWidth()
            let (tree, text) = Self.split(label)
            // The label tab rises over pane content: give it a second coat so
            // it reads as the folder's edge sitting *on* the bar, not a stain.
            // The coat stops at the cell's top edge — the tab tucks *under*
            // the cell, the way a folder's tab does (owner call 2026-09-08).
            let tabPath = NSBezierPath()
            tabPath.move(to: NSPoint(x: 0, y: cellTop))
            tabPath.appendArc(from: NSPoint(x: 0, y: bounds.height), to: NSPoint(x: tabWidth, y: bounds.height), radius: r)
            tabPath.appendArc(from: NSPoint(x: tabWidth, y: bounds.height), to: NSPoint(x: tabWidth, y: cellTop), radius: r)
            tabPath.line(to: NSPoint(x: tabWidth, y: cellTop))
            tabPath.close()
            coat.setFill()
            tabPath.fill()
            var textX: CGFloat = 7
            if tree {
                let glyph = NSRect(x: 6.5, y: cellTop + (Self.tabHeight - 10) / 2, width: 10, height: 10)
                Theme.Folder.labelText.setFill()
                Self.treePath(in: glyph).fill()
                textX += Self.treeGlyphWidth
            }
            let attributed = NSAttributedString(string: text, attributes: labelAttributes)
            let size = attributed.size()
            let rect = NSRect(
                x: textX,
                y: cellTop + (Self.tabHeight - size.height) / 2 + 0.5,
                width: tabWidth - textX - 7,
                height: size.height
            )
            attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let onRemove, let label else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard point.y >= bounds.height - Self.tabHeight, point.x <= labelTabWidth() else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: "Remove worktree \(label)…", action: #selector(removeTapped), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        _ = onRemove
        return menu
    }

    @objc private func removeTapped() { onRemove?() }
}

private final class HoverFadeButton: NSButton {
    static let restingAlpha: CGFloat = 0.55
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { alphaValue = 1.0 }
    override func mouseExited(with event: NSEvent) { alphaValue = Self.restingAlpha }
}

/// A 6 pt attention dot drawn as a centered sublayer, so scale animations
/// (the green arrival) grow from the dot's middle rather than a view corner.
private final class BadgeDotView: NSView {
    let dotLayer = CALayer()

    init(color: NSColor) {
        super.init(frame: CGRect(x: 0, y: 0, width: 6, height: 6))
        wantsLayer = true
        dotLayer.backgroundColor = color.cgColor
        dotLayer.cornerRadius = 3
        dotLayer.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
        dotLayer.position = CGPoint(x: 3, y: 3)
        layer?.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize { NSSize(width: 6, height: 6) }
}

/// The clock colon's sine breath (§1.1 motion inventory item 3): ~1 Hz opacity
/// ease — a breath, not a blink. The animation must be (re)installed whenever
/// the backing layer joins a layer tree; animations added before the view is
/// in a window are silently dropped by AppKit's layer management.
private final class BreathingColonLabel: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        guard window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              layer?.animation(forKey: "colonBreath") == nil else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = 1.0
        breath.toValue = 0.45
        breath.duration = 0.5
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(breath, forKey: "colonBreath")
    }
}

private extension DateFormatter {
    /// Cheap reuse — a couple of fixed-format formatters created once.
    static var cache: [String: DateFormatter] = [:]
    static func cached(_ format: String) -> DateFormatter {
        if let f = cache[format] { return f }
        let f = DateFormatter()
        f.dateFormat = format
        cache[format] = f
        return f
    }
}

/// The branch chip a folder label reveals on hover: `⎇ branch` in mono on
/// the folder's own tint, opaque enough to read over pane content. Inert to
/// the pointer — it answers, it doesn't offer.
private final class BranchRevealView: NSView {
    private let label: NSTextField

    init(branch: String, fill: NSColor) {
        label = NSTextField(labelWithString: "⎇ \(branch)")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = Theme.Elevation.radiusSmall
        shadow = Theme.Elevation.raisedShadow
        label.font = Theme.Typography.mono(Theme.Typography.small, weight: .medium)
        label.textColor = Theme.chromeText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

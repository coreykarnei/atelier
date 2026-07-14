import AppKit

protocol BottomBarDelegate: AnyObject {
    func bottomBarDidSelectSession(at index: Int)
    func bottomBarDidRequestNewSession()
    func bottomBarDidRequestCloseSession(at index: Int)
    func bottomBarDidRequestRenameSession(at index: Int)
    func bottomBarDidToggleLayout()
    func bottomBarDidClickPill(anchor: NSView)
}

/// Everything one session tab needs to draw. `id` is the session's stable
/// identity (tab views persist across updates so state changes can animate);
/// `index` is its position in the window's session list at this instant.
struct SessionTabInfo {
    let id: UUID
    let index: Int
    let title: String
    let isWorktree: Bool
    /// Group boundary marker — tabs sharing a root sit together (MILESTONE_1 §7);
    /// the grouping *is* how codebase sharing is shown.
    let groupKey: String
    let attention: Session.Attention
    /// When the attention state began — surfaced only in the hover tooltip
    /// (§1.3: time on inquiry, never pushed).
    let attentionSince: Date?
}

/// The bottom bar (MILESTONE_1 §7, polished per POLISH_PLAN §3). Static project
/// pill on the left (the worktree fan's trigger), session tabs grouped by root
/// in the middle — wrapping to a second row group-aware when full, with a `»`
/// overflow menu as the hard ceiling — and the clock + layout toggle on the
/// right. Styling follows the tmux status bar this app succeeds: blue pill,
/// green active tab, dark text on both.
///
/// Tab views are *persistent* (keyed by session id) and laid out by hand, so
/// width changes glide (a Claude title rewrite slides neighbors instead of
/// twitching them) and attention changes cross-fade in place.
final class BottomBar: NSView {
    weak var delegate: BottomBarDelegate?

    static let rowHeight: CGFloat = 30
    static let twoRowHeight: CGFloat = 54
    private static let tabHeight: CGFloat = 20
    private static let rowGap: CGFloat = 4

    /// The bar's current natural height (one or two tab rows).
    private(set) var desiredHeight: CGFloat = BottomBar.rowHeight
    /// Fired when `desiredHeight` changes so the owner can resize the constraint.
    var onDesiredHeightChange: ((CGFloat) -> Void)?

    /// Anchor for surfaces that fan from the pill.
    var pillAnchor: NSView { pillView }

    private let pillView = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    /// Manual-layout home of the tab views; sits between pill and clock.
    private let tabsArea = NSView()
    private let addButton = NSButton()
    private let overflowButton = NSButton()
    private let clockPrefixLabel = NSTextField(labelWithString: "")
    private let clockColonLabel = BreathingColonLabel(labelWithString: ":")
    private let clockSuffixLabel = NSTextField(labelWithString: "")
    private let layoutButton = NSButton()
    private let topBorder = NSBox()

    private var tabs: [SessionTabInfo] = []
    private var activeIndex = 0
    private var tabViews: [UUID: SessionTabView] = [:]
    private var separatorPool: [NSView] = []
    private var lastFlowWidth: CGFloat = 0
    private var lastFlowHeight: CGFloat = 0
    /// First population per launch gets the restore stagger (§5); afterwards
    /// arrivals appear with a plain fade, never again.
    private var hasRevealed = false

    private var clockTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        build()
        startClock()
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
        clockTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    private func build() {
        topBorder.boxType = .custom
        topBorder.fillColor = Theme.Elevation.frameLine
        topBorder.borderWidth = 0
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = Theme.accentBlue.cgColor
        pillView.layer?.cornerRadius = Theme.Elevation.radiusSmall
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pillClicked)))
        addSubview(pillView)

        // The pill carries the project name — a path component, so mono (§1.4).
        pillLabel.font = Theme.Typography.mono(Theme.Typography.small, weight: .semibold)
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
            label.font = Theme.Typography.mono(Theme.Typography.small)
            label.textColor = Theme.chromeMutedText
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        configureIconButton(layoutButton, symbol: "rectangle.split.3x1", action: #selector(layoutTapped))
        // The toggle is constraint-anchored (unlike the flow-placed buttons,
        // which are positioned by frame inside tabsArea).
        layoutButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layoutButton)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            pillView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.heightAnchor.constraint(equalToConstant: Self.tabHeight),
            pillLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 8),
            pillLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -8),
            pillLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            pillLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220),

            layoutButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            layoutButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            layoutButton.widthAnchor.constraint(equalToConstant: 22),
            layoutButton.heightAnchor.constraint(equalToConstant: 22),

            // One cap-height (§3 micro-pass): same mono face and size as the
            // pill label, centered on the same axis — identical baselines
            // without cross-branch baseline constraints (which AppKit's
            // window-sizing pass mishandles; see the tabsArea note below).
            clockSuffixLabel.trailingAnchor.constraint(equalTo: layoutButton.leadingAnchor, constant: -12),
            clockSuffixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            clockColonLabel.trailingAnchor.constraint(equalTo: clockSuffixLabel.leadingAnchor),
            clockColonLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            clockPrefixLabel.trailingAnchor.constraint(equalTo: clockColonLabel.leadingAnchor),
            clockPrefixLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            tabsArea.leadingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: 14),
            tabsArea.trailingAnchor.constraint(lessThanOrEqualTo: clockPrefixLabel.leadingAnchor, constant: -12),
        ])
        // The trailing equality must NOT be required: a closed required chain
        // from leading to trailing lets AppKit "resolve" the window width from
        // constraints (it collapsed the window to ~10 pt). Stretch by desire.
        let stretch = tabsArea.trailingAnchor.constraint(equalTo: clockPrefixLabel.leadingAnchor, constant: -12)
        stretch.priority = .defaultLow
        // And the vertical pins yield while the bar is hidden at height 0.
        let top = tabsArea.topAnchor.constraint(equalTo: topAnchor, constant: 1)
        top.priority = NSLayoutConstraint.Priority(999)
        let bottom = tabsArea.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottom.priority = NSLayoutConstraint.Priority(999)
        NSLayoutConstraint.activate([stretch, top, bottom])
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
        self.tabs = tabs
        self.activeIndex = activeIndex

        pillLabel.stringValue = pill
        pillView.isHidden = pill.isEmpty

        layoutButton.isHidden = mode == nil
        let symbol = mode == .triptych ? "rectangle.split.3x1" : "rectangle.split.1x2"
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

    /// One item the flow can place: a tab, a group separator, or a button.
    private enum FlowItem {
        case tab(SessionTabInfo)
        case separator
        case overflow
        case add

        func width(of bar: BottomBar) -> CGFloat {
            switch self {
            case .tab(let info): return SessionTabView.desiredWidth(for: info, isActive: info.index == bar.activeIndex)
            case .separator: return 9
            case .overflow, .add: return 26
            }
        }
    }

    /// Lay tabs into one or two rows, never splitting a root group across rows
    /// unless the group alone exceeds a full row. Beyond two rows, the remainder
    /// collapses into a `»` menu — the bar must not grow into a third pane.
    ///
    /// Tab views are reused by session id: frame changes glide (~200 ms) when
    /// `animated`, so a title rewrite slides neighbors instead of snapping them
    /// (MILESTONE_1 §12 risk 2, retired here).
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

        // Pack into at most two rows.
        var rows: [[FlowItem]] = [[]]
        var widths: [CGFloat] = [0]
        var overflow: [SessionTabInfo] = []

        func tryAppend(_ item: FlowItem) -> Bool {
            let w = item.width(of: self) + (rows[rows.count - 1].isEmpty ? 0 : 4)
            if widths[rows.count - 1] + w > rowWidth, !rows[rows.count - 1].isEmpty {
                guard rows.count < 2 else { return false }
                rows.append([])
                widths.append(0)
            }
            rows[rows.count - 1].append(item)
            widths[rows.count - 1] += w
            return true
        }

        outer: for (chunkIndex, chunk) in chunks.enumerated() {
            let chunkWidth = chunk.reduce(0) { $0 + SessionTabView.desiredWidth(for: $1, isActive: $1.index == activeIndex) + 4 }
            // Try to keep the whole group on one row: jump rows if it won't fit here.
            if chunkWidth <= rowWidth, widths[rows.count - 1] + chunkWidth > rowWidth,
               !rows[rows.count - 1].isEmpty, rows.count < 2 {
                rows.append([])
                widths.append(0)
            }
            for (i, tab) in chunk.enumerated() {
                if chunkIndex > 0 && i == 0 {
                    _ = tryAppend(.separator)
                }
                if !tryAppend(.tab(tab)) {
                    overflow.append(contentsOf: chunk[i...])
                    for rest in chunks[(chunkIndex + 1)...] { overflow.append(contentsOf: rest) }
                    break outer
                }
            }
        }

        if overflow.isEmpty {
            overflowButton.isHidden = true
        } else {
            overflowButton.isHidden = false
            overflowButton.menu = overflowMenu(for: overflow)
            overflowButton.action = #selector(overflowTapped)
            _ = tryAppend(.overflow)
        }
        _ = tryAppend(.add)

        place(rows: rows, animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        let newHeight = rows.count > 1 ? Self.twoRowHeight : Self.rowHeight
        if newHeight != desiredHeight {
            desiredHeight = newHeight
            onDesiredHeightChange?(newHeight)
        }
    }

    /// Materialize the flow: persistent views move to their new frames (gliding
    /// when animated), departed tabs fade out, arrivals fade in in place.
    private func place(rows: [[FlowItem]], animated: Bool) {
        var seen = Set<UUID>()
        var separatorsUsed = 0
        var placements: [(NSView, CGRect)] = []
        var arrivals: [NSView] = []

        let areaHeight = tabsArea.bounds.height
        let contentHeight = rows.count > 1
            ? Self.tabHeight * 2 + Self.rowGap
            : Self.tabHeight
        let topY = (areaHeight + contentHeight) / 2 - Self.tabHeight

        for (rowIndex, row) in rows.enumerated() {
            var x: CGFloat = 0
            let y = topY - CGFloat(rowIndex) * (Self.tabHeight + Self.rowGap)
            for item in row {
                let width = item.width(of: self)
                switch item {
                case .tab(let info):
                    seen.insert(info.id)
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
                    placements.append((view, CGRect(x: x, y: y, width: width, height: Self.tabHeight)))
                case .separator:
                    let line = dequeueSeparator(at: separatorsUsed)
                    separatorsUsed += 1
                    placements.append((line, CGRect(x: x + 4, y: y + 3, width: 1, height: 14)))
                case .overflow:
                    placements.append((overflowButton, CGRect(x: x + 2, y: y, width: 22, height: Self.tabHeight)))
                case .add:
                    placements.append((addButton, CGRect(x: x + 2, y: y, width: 22, height: Self.tabHeight)))
                }
                x += width + 4
            }
        }

        // Departed tabs (closed, or pushed into the overflow menu).
        for (id, view) in tabViews where !seen.contains(id) {
            tabViews[id] = nil
            if animated {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.15
                    view.animator().alphaValue = 0
                }, completionHandler: { view.removeFromSuperview() })
            } else {
                view.removeFromSuperview()
            }
        }
        for index in separatorsUsed..<separatorPool.count {
            separatorPool[index].isHidden = true
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

    private func dequeueSeparator(at index: Int) -> NSView {
        if index < separatorPool.count {
            separatorPool[index].isHidden = false
            return separatorPool[index]
        }
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.Elevation.frameLine.cgColor
        separatorPool.append(line)
        tabsArea.addSubview(line)
        return line
    }

    private func wire(_ view: SessionTabView) {
        view.onSelect = { [weak self] idx in self?.delegate?.bottomBarDidSelectSession(at: idx) }
        view.onClose = { [weak self] idx in self?.delegate?.bottomBarDidRequestCloseSession(at: idx) }
        view.onRename = { [weak self] idx in self?.delegate?.bottomBarDidRequestRenameSession(at: idx) }
    }

    private func overflowMenu(for tabs: [SessionTabInfo]) -> NSMenu {
        let menu = NSMenu()
        for tab in tabs {
            let item = NSMenuItem(title: tab.title, action: #selector(overflowItemSelected(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tab.index
            menu.addItem(item)
        }
        return menu
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
    @objc private func pillClicked() { delegate?.bottomBarDidClickPill(anchor: pillView) }
    @objc private func overflowTapped() {
        overflowButton.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: overflowButton.bounds.maxY), in: overflowButton)
    }
    @objc private func overflowItemSelected(_ sender: NSMenuItem) {
        delegate?.bottomBarDidSelectSession(at: sender.tag)
    }
}

/// A single session tab: optional attention badge, ⎇ glyph for worktree
/// sessions, ellipsized title. The active tab — and only the active tab —
/// carries a close `×` at its leading edge, before the title: the tab you can
/// close is the one you're looking at, and inactive tabs stay quiet. Click
/// selects; double-click renames. Persistent across bar updates so its state
/// changes can animate:
/// attention cross-fades (~250 ms), a green arrival does one soft scale-in,
/// the working blue carries the ~4 s subliminal pulse, and the peach `!`
/// **never** animates — urgency reads as stillness (§1.3).
private final class SessionTabView: NSView {
    let sessionId: UUID
    private(set) var index: Int = -1
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = HoverFadeButton()
    private var badgeView: NSView?
    private var attention: Session.Attention = .none
    private var attentionSince: Date?
    private var isActive = false
    private var applied = false
    private var toolTipRect: CGRect = .null

    init(sessionId: UUID) {
        self.sessionId = sessionId
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusSmall

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
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
    /// wrap and the `»` overflow absorb long ones. Mono is width-stable across
    /// the regular/semibold active swap.
    static func desiredWidth(for info: SessionTabInfo, isActive: Bool) -> CGFloat {
        let label = (info.isWorktree ? "⎇ " : "") + (info.title.isEmpty ? "untitled" : info.title)
        // Measure at the active (semibold) weight — a hair wider than regular
        // at this size, and the estimate must never come in under the truth.
        let font = Theme.Typography.mono(Theme.Typography.small, weight: .semibold)
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        let badge: CGFloat = info.attention == .none ? 0 : 11
        return ceil(textWidth) + badge + (isActive ? 34 : 20)
    }

    func apply(info: SessionTabInfo, isActive: Bool) {
        index = info.index
        let text = (info.isWorktree ? "⎇ " : "") + (info.title.isEmpty ? "untitled" : info.title)
        if titleLabel.stringValue != text { titleLabel.stringValue = text }

        if self.isActive != isActive || !applied {
            self.isActive = isActive
            // Active tab wears the tmux green; inactive tabs stay quiet.
            layer?.backgroundColor = (isActive ? Theme.accentGreen : .clear).cgColor
            titleLabel.font = Theme.Typography.mono(Theme.Typography.small, weight: isActive ? .semibold : .regular)
            titleLabel.textColor = isActive ? Theme.accentTextDark : Theme.chromeMutedText
            closeButton.contentTintColor = Theme.accentTextDark
            closeButton.isHidden = !isActive
            closeButton.alphaValue = HoverFadeButton.restingAlpha
        }
        attentionSince = info.attentionSince
        setAttention(info.attention, animated: applied)
        applied = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let closeWidth: CGFloat = 12
        if !closeButton.isHidden {
            closeButton.frame = CGRect(
                x: 6,
                y: (bounds.height - closeWidth) / 2,
                width: closeWidth,
                height: closeWidth
            )
        }
        // Everything else flows after the close `×` when it's present.
        let leading: CGFloat = closeButton.isHidden ? 8 : 22
        let hasBadge = badgeView != nil
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
            y: (bounds.height - titleHeight) / 2,
            width: max(0, bounds.width - titleX - 8),
            height: titleHeight
        )
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
        if event.clickCount == 2 {
            onRename?(index)
        } else {
            onSelect?(index)
        }
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

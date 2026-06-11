import AppKit

protocol BottomBarDelegate: AnyObject {
    func bottomBarDidSelectSession(at index: Int)
    func bottomBarDidRequestNewSession()
    func bottomBarDidRequestCloseSession(at index: Int)
    func bottomBarDidRequestRenameSession(at index: Int)
    func bottomBarDidToggleLayout()
    func bottomBarDidClickPill(anchor: NSView)
}

/// Everything one session tab needs to draw. `index` is the session's index in the
/// window's session list (display order may differ — tabs are grouped by root).
struct SessionTabInfo {
    let index: Int
    let title: String
    let isWorktree: Bool
    /// Group boundary marker — tabs sharing a root sit together (MILESTONE_1 §7);
    /// the grouping *is* how codebase sharing is shown.
    let groupKey: String
    let attention: Session.Attention
}

/// The bottom bar (MILESTONE_1 §7). Static project pill on the left (the worktree
/// fan's trigger), session tabs grouped by root in the middle — wrapping to a
/// second row group-aware when full, with a `»` overflow menu as the hard ceiling —
/// and the clock + layout toggle on the right. Styling follows the tmux status bar
/// this app succeeds: blue pill, green active tab, dark text on both.
final class BottomBar: NSView {
    weak var delegate: BottomBarDelegate?

    static let rowHeight: CGFloat = 30
    static let twoRowHeight: CGFloat = 54

    /// The bar's current natural height (one or two tab rows).
    private(set) var desiredHeight: CGFloat = BottomBar.rowHeight
    /// Fired when `desiredHeight` changes so the owner can resize the constraint.
    var onDesiredHeightChange: ((CGFloat) -> Void)?

    /// Anchor for surfaces that fan from the pill.
    var pillAnchor: NSView { pillView }

    private let pillView = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private let addButton = NSButton()
    private let overflowButton = NSButton()
    private let clockLabel = NSTextField(labelWithString: "")
    private let layoutButton = NSButton()
    private let topBorder = NSBox()

    private var tabs: [SessionTabInfo] = []
    private var activeIndex = 0
    private var lastFlowWidth: CGFloat = 0

    private var clockTimer: Timer?
    private var colonVisible = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.bottomBarBackground.cgColor
        build()
        startClock()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { clockTimer?.invalidate() }

    override func updateLayer() {
        layer?.backgroundColor = Theme.bottomBarBackground.cgColor
    }

    private func build() {
        topBorder.boxType = .custom
        topBorder.fillColor = Theme.bottomBarBorder
        topBorder.borderWidth = 0
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        pillView.wantsLayer = true
        pillView.layer?.backgroundColor = Theme.accentBlue.cgColor
        pillView.layer?.cornerRadius = 4
        pillView.translatesAutoresizingMaskIntoConstraints = false
        pillView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pillClicked)))
        addSubview(pillView)

        pillLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        pillLabel.textColor = Theme.accentTextDark
        pillLabel.lineBreakMode = .byTruncatingMiddle
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(pillLabel)

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 2
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        configureIconButton(addButton, symbol: "plus", action: #selector(addTapped))
        configureIconButton(overflowButton, symbol: "chevron.right.2", action: nil)
        overflowButton.isHidden = true

        clockLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        clockLabel.textColor = Theme.chromeMutedText
        clockLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clockLabel)

        configureIconButton(layoutButton, symbol: "rectangle.split.3x1", action: #selector(layoutTapped))
        addSubview(layoutButton)

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1),

            pillView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            pillView.centerYAnchor.constraint(equalTo: centerYAnchor),
            pillView.heightAnchor.constraint(equalToConstant: 20),
            pillLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 8),
            pillLabel.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -8),
            pillLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            pillLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 220),

            layoutButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            layoutButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            layoutButton.widthAnchor.constraint(equalToConstant: 22),
            layoutButton.heightAnchor.constraint(equalToConstant: 22),

            clockLabel.trailingAnchor.constraint(equalTo: layoutButton.leadingAnchor, constant: -12),
            clockLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            rowsStack.leadingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: 14),
            rowsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            rowsStack.trailingAnchor.constraint(lessThanOrEqualTo: clockLabel.leadingAnchor, constant: -12),
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector?) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = Theme.chromeMutedText
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
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

        flowTabs()
    }

    override func layout() {
        super.layout()
        // Re-flow when the bar is resized enough to change what fits.
        if abs(bounds.width - lastFlowWidth) > 40 { flowTabs() }
    }

    /// Lay tabs into one or two rows, never splitting a root group across rows
    /// unless the group alone exceeds a full row. Beyond two rows, the remainder
    /// collapses into a `»` menu — the bar must not grow into a third pane.
    private func flowTabs() {
        lastFlowWidth = bounds.width
        for view in rowsStack.arrangedSubviews { view.removeFromSuperview() }

        // Group chunks: runs of consecutive tabs sharing a root.
        var chunks: [[SessionTabInfo]] = []
        for tab in tabs {
            if let last = chunks.last, last.first?.groupKey == tab.groupKey {
                chunks[chunks.count - 1].append(tab)
            } else {
                chunks.append([tab])
            }
        }

        let reservedRight: CGFloat = 170 // clock + toggle + spacing
        let reservedLeft = pillView.isHidden ? 24 : pillLabel.intrinsicContentSize.width + 16 + 24
        let rowWidth = max(240, bounds.width - reservedLeft - reservedRight)

        var rows: [[NSView]] = [[]]
        var widths: [CGFloat] = [0]
        var overflow: [SessionTabInfo] = []

        func append(_ view: NSView, width: CGFloat, breakable: Bool) -> Bool {
            let row = rows.count - 1
            if widths[row] + width > rowWidth, !rows[row].isEmpty {
                guard rows.count < 2 else { return false }
                rows.append([])
                widths.append(0)
            }
            rows[rows.count - 1].append(view)
            widths[rows.count - 1] += width
            return true
        }

        outer: for (chunkIndex, chunk) in chunks.enumerated() {
            let chunkWidth = chunk.reduce(0) { $0 + tabWidth($1) } + (chunkIndex > 0 ? 9 : 0)
            let fitsAsGroup = chunkWidth <= rowWidth
            // Try to keep the whole group on one row: jump rows if it won't fit here.
            if fitsAsGroup, widths[rows.count - 1] + chunkWidth > rowWidth, !rows[rows.count - 1].isEmpty, rows.count < 2 {
                rows.append([])
                widths.append(0)
            }
            for (i, tab) in chunk.enumerated() {
                if chunkIndex > 0 && i == 0 {
                    _ = append(makeSeparator(), width: 9, breakable: true)
                }
                let view = SessionTabView(info: tab, isActive: tab.index == activeIndex)
                wire(view)
                if !append(view, width: tabWidth(tab), breakable: true) {
                    overflow.append(contentsOf: chunk[i...])
                    for rest in chunks[(chunkIndex + 1)...] { overflow.append(contentsOf: rest) }
                    break outer
                }
            }
        }

        // Overflow menu, then the trailing `+`.
        if overflow.isEmpty {
            overflowButton.isHidden = true
        } else {
            overflowButton.isHidden = false
            overflowButton.menu = overflowMenu(for: overflow)
            overflowButton.action = #selector(overflowTapped)
            _ = append(overflowButton, width: 26, breakable: true)
        }
        _ = append(addButton, width: 26, breakable: true)

        for row in rows where !row.isEmpty {
            let rowStack = NSStackView(views: row)
            rowStack.orientation = .horizontal
            rowStack.spacing = 4
            rowStack.alignment = .centerY
            rowsStack.addArrangedSubview(rowStack)
        }

        let newHeight = rows.count > 1 ? Self.twoRowHeight : Self.rowHeight
        if newHeight != desiredHeight {
            desiredHeight = newHeight
            onDesiredHeightChange?(newHeight)
        }
    }

    private func wire(_ view: SessionTabView) {
        view.onSelect = { [weak self] idx in self?.delegate?.bottomBarDidSelectSession(at: idx) }
        view.onClose = { [weak self] idx in self?.delegate?.bottomBarDidRequestCloseSession(at: idx) }
        view.onRename = { [weak self] idx in self?.delegate?.bottomBarDidRequestRenameSession(at: idx) }
    }

    /// Estimated width: label (capped) + glyphs + close + padding.
    private func tabWidth(_ tab: SessionTabInfo) -> CGFloat {
        let label = (tab.isWorktree ? "⎇ " : "") + tab.title
        let textWidth = min(
            (label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width,
            160
        )
        let badge: CGFloat = tab.attention == .none ? 0 : 10
        return textWidth + badge + 38
    }

    private func makeSeparator() -> NSView {
        let line = NSBox()
        line.boxType = .custom
        line.fillColor = Theme.bottomBarBorder
        line.borderWidth = 0
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 14),
        ])
        return line
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
        colonVisible.toggle()
        let now = Date()
        let time = DateFormatter.cached("HH:mm").string(from: now)
        let date = DateFormatter.cached("MMM dd").string(from: now)
        let shownTime = colonVisible ? time : time.replacingOccurrences(of: ":", with: " ")
        clockLabel.stringValue = "\(shownTime) · \(date)"
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

/// A single session tab: optional attention dot, ⎇ glyph for worktree sessions,
/// ellipsized title, close affordance. Click selects; double-click renames.
private final class SessionTabView: NSView {
    let index: Int
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onRename: ((Int) -> Void)?

    init(info: SessionTabInfo, isActive: Bool) {
        self.index = info.index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        // Active tab wears the tmux green; inactive tabs stay quiet.
        layer?.backgroundColor = (isActive ? Theme.accentGreen : .clear).cgColor

        var leading: NSLayoutXAxisAnchor = leadingAnchor
        var leadingPad: CGFloat = 8

        // Attention badge (MILESTONE_1 §7.1) — always visible: the agent's exact
        // state, read peripherally. Dots for working/waiting/done-unseen; a `!`
        // when the agent is explicitly blocked on you.
        if info.attention != .none {
            let badge: NSView
            if info.attention == .needsInput {
                let mark = NSTextField(labelWithString: "!")
                mark.font = .systemFont(ofSize: 11, weight: .heavy)
                mark.textColor = Theme.accentPeach
                badge = mark
            } else {
                let dot = NSView()
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 3
                dot.layer?.backgroundColor = Self.badgeColor(info.attention).cgColor
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 6),
                    dot.heightAnchor.constraint(equalToConstant: 6),
                ])
                badge = dot
            }
            badge.translatesAutoresizingMaskIntoConstraints = false
            addSubview(badge)
            NSLayoutConstraint.activate([
                badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
            leading = badge.trailingAnchor
            leadingPad = 5
        }

        let text = (info.isWorktree ? "⎇ " : "") + (info.title.isEmpty ? "untitled" : info.title)
        let titleLabel = NSTextField(labelWithString: text)
        titleLabel.font = .systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
        titleLabel.textColor = isActive ? Theme.accentTextDark : Theme.chromeMutedText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let closeButton = NSButton()
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close session")
        closeButton.contentTintColor = isActive ? Theme.accentTextDark : Theme.chromeMutedText
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .medium)
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        let width = titleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 160)
        width.priority = .required
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: leading, constant: leadingPad),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            width,
            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 12),
            closeButton.heightAnchor.constraint(equalToConstant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func badgeColor(_ attention: Session.Attention) -> NSColor {
        switch attention {
        case .none: return .clear
        case .working: return Theme.accentBlue
        case .waiting: return Theme.accentPeach
        case .needsInput: return Theme.accentPeach // rendered as `!`, not a dot
        case .doneUnseen: return Theme.accentGreen
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onRename?(index)
        } else {
            onSelect?(index)
        }
    }

    @objc private func closeTapped() { onClose?(index) }
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

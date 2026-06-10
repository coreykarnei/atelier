import AppKit

protocol BottomBarDelegate: AnyObject {
    func bottomBarDidSelectSession(at index: Int)
    func bottomBarDidRequestNewSession()
    func bottomBarDidRequestCloseSession(at index: Int)
    func bottomBarDidToggleLayout()
    func bottomBarDidClickPill(anchor: NSView)
}

/// The bottom bar (MILESTONE_1 §7). For M1.2 it carries the session tab strip, a `+`
/// to add sessions, the location pill on the left, and a clock + layout-toggle on the
/// right. Styling follows the tmux status bar this app succeeds: a blue-filled pill,
/// a green-filled active tab, dark text on both. The pill becomes the clickable
/// worktree fan in M1.4; per-session attention state on the tabs is deferred (§7.1).
final class BottomBar: NSView {
    weak var delegate: BottomBarDelegate?

    static let height: CGFloat = 30

    private let pillView = NSView()
    private let pillLabel = NSTextField(labelWithString: "")
    private let tabsStack = NSStackView()
    private let addButton = NSButton()
    private let clockLabel = NSTextField(labelWithString: "")
    private let layoutButton = NSButton()
    private let topBorder = NSBox()

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
        // The pill is the worktree fan's trigger (MILESTONE_1 §6).
        pillView.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(pillClicked)))
        addSubview(pillView)

        pillLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        pillLabel.textColor = Theme.accentTextDark
        pillLabel.lineBreakMode = .byTruncatingMiddle
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pillView.addSubview(pillLabel)

        tabsStack.orientation = .horizontal
        tabsStack.spacing = 4
        tabsStack.alignment = .centerY
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        tabsStack.setHuggingPriority(.defaultHigh, for: .horizontal)
        addSubview(tabsStack)

        configureIconButton(addButton, symbol: "plus", action: #selector(addTapped))
        addSubview(addButton)

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

            tabsStack.leadingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: 14),
            tabsStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tabsStack.trailingAnchor.constraint(lessThanOrEqualTo: clockLabel.leadingAnchor, constant: -12),

            addButton.widthAnchor.constraint(equalToConstant: 22),
            addButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.contentTintColor = Theme.chromeMutedText
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: Update

    /// Rebuild the tab strip and refresh the chrome for the current session set.
    /// `pill` is the active session's location (branch or folder); `mode` is nil for
    /// a Landing, which has no layout to toggle.
    func update(titles: [String], activeIndex: Int, pill: String, mode: LayoutMode?) {
        pillLabel.stringValue = pill
        pillView.isHidden = pill.isEmpty

        // Rebuild tabs. (M1.2 is a single row; grouping/wrap arrive with worktrees.)
        for view in tabsStack.arrangedSubviews { view.removeFromSuperview() }
        for (i, title) in titles.enumerated() {
            let tab = SessionTabView(index: i, title: title, isActive: i == activeIndex)
            tab.onSelect = { [weak self] idx in self?.delegate?.bottomBarDidSelectSession(at: idx) }
            tab.onClose = { [weak self] idx in self?.delegate?.bottomBarDidRequestCloseSession(at: idx) }
            tabsStack.addArrangedSubview(tab)
        }
        tabsStack.addArrangedSubview(addButton)

        layoutButton.isHidden = mode == nil
        let symbol = mode == .triptych ? "rectangle.split.3x1" : "rectangle.split.1x2"
        layoutButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Toggle layout")
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
}

/// A single session tab: ellipsized title plus a close affordance. Clicking the body
/// selects the session; clicking the `×` closes it.
private final class SessionTabView: NSView {
    let index: Int
    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()

    init(index: Int, title: String, isActive: Bool) {
        self.index = index
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        // Active tab wears the tmux green; inactive tabs stay quiet.
        layer?.backgroundColor = (isActive ? Theme.accentGreen : .clear).cgColor

        titleLabel.stringValue = title.isEmpty ? "untitled" : title
        titleLabel.font = .systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
        titleLabel.textColor = isActive ? Theme.accentTextDark : Theme.chromeMutedText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

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
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
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

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
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

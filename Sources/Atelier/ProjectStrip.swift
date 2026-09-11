import AppKit

/// One project tab's display state.
struct ProjectTabInfo {
    let id: ObjectIdentifier
    let title: String
    let isActive: Bool
    /// The attention marks of the project's sessions, in tab order, states
    /// with nothing to say already dropped.
    let marks: [Session.Attention]
}

/// The project tab row under the titlebar (2026-09-10): Atelier's own tabs,
/// replacing native window tabbing — same shape (a full-width row, tabs
/// dividing it equally, shown once there are two), our material. The
/// active tab is a rounded chip in the panes' base, flush with the content;
/// the others sit darker in crust. Every tab carries its
/// sessions' attention marks after the title (blue working, peach waiting,
/// peach `!` blocked, green unseen completion), so a project you're not
/// looking at still says where its agents stand. `+` opens a new project
/// tab; the active tab's `×` closes it. Gaps pass clicks through to the
/// wash (drag to move, double-click to zoom).
final class ProjectStripView: NSView {
    var onSelect: ((ObjectIdentifier) -> Void)?
    var onClose: ((ObjectIdentifier) -> Void)?
    var onNew: (() -> Void)?

    static let rowHeight: CGFloat = 28
    static let tabHeight: CGFloat = 22
    static let gap: CGFloat = 4
    static let plusWidth: CGFloat = 28

    private var tabs: [ProjectTabView] = []
    private let newButton = StripHoverButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        newButton.bezelStyle = .regularSquare
        newButton.isBordered = false
        newButton.imagePosition = .imageOnly
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New project tab")
        newButton.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        newButton.contentTintColor = Theme.chromeMutedText
        newButton.toolTip = "New Project Tab  ⌘T"
        newButton.target = self
        newButton.action = #selector(newTapped)
        addSubview(newButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Gaps belong to the titlebar (window drag / double-click zoom), not to
    /// the strip.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    func update(tabs infos: [ProjectTabInfo]) {
        var existing: [ObjectIdentifier: ProjectTabView] = [:]
        for tab in tabs { existing[tab.id] = tab }
        var next: [ProjectTabView] = []
        for info in infos {
            let tab = existing.removeValue(forKey: info.id) ?? makeTab(id: info.id)
            tab.apply(info)
            next.append(tab)
        }
        for (_, gone) in existing { gone.removeFromSuperview() }
        tabs = next
        needsLayout = true
    }

    private func makeTab(id: ObjectIdentifier) -> ProjectTabView {
        let tab = ProjectTabView(id: id)
        tab.onSelect = { [weak self] in self?.onSelect?(id) }
        tab.onClose = { [weak self] in self?.onClose?(id) }
        addSubview(tab)
        return tab
    }

    override func layout() {
        super.layout()
        let height = Self.tabHeight
        let y = (bounds.height - height) / 2
        // Equal shares of the row, the `+` pinned at the trailing edge.
        let inset: CGFloat = 6
        let available = bounds.width - inset - Self.plusWidth - Self.gap * CGFloat(tabs.count)
        let width = tabs.isEmpty ? 0 : floor(available / CGFloat(tabs.count))
        var x = inset
        for tab in tabs {
            tab.frame = CGRect(x: x, y: y, width: width, height: height)
            x += width + Self.gap
        }
        newButton.frame = CGRect(x: bounds.width - Self.plusWidth, y: (bounds.height - Self.plusWidth) / 2,
                                 width: Self.plusWidth, height: Self.plusWidth)
    }

    @objc private func newTapped() { onNew?() }
}

/// A single project tab: title, the sessions' marks, the `×` on the active
/// tab (revealed on hover, slot reserved so nothing shifts).
private final class ProjectTabView: NSView {
    let id: ObjectIdentifier
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = StripHoverButton()
    private var markViews: [NSView] = []
    private var isActive = false
    private var hovered = false
    private var tracking: NSTrackingArea?

    private static let closeWidth: CGFloat = 12
    private static let closeSlot: CGFloat = 6 + 12 + 6
    private static let markGap: CGFloat = 6
    private static let dot: CGFloat = 5
    private static let dotGap: CGFloat = 3

    override var mouseDownCanMoveWindow: Bool { false }

    init(id: ObjectIdentifier) {
        self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusMedium

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = Theme.Typography.mono(Theme.Typography.small, weight: .medium)
        addSubview(titleLabel)

        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close project")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .medium)
        closeButton.contentTintColor = Theme.chromeText
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        closeButton.alphaValue = 0
        addSubview(closeButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var marksWidth: CGFloat {
        guard !markViews.isEmpty else { return 0 }
        let n = CGFloat(markViews.count)
        return Self.markGap + n * Self.dot + (n - 1) * Self.dotGap
    }

    func apply(_ info: ProjectTabInfo) {
        if titleLabel.stringValue != info.title { titleLabel.stringValue = info.title }
        isActive = info.isActive
        closeButton.isHidden = !isActive
        toolTip = info.title
        for view in markViews { view.removeFromSuperview() }
        markViews = info.marks.map { mark in
            let view = Self.makeMark(mark)
            addSubview(view)
            return view
        }
        restyle()
        needsLayout = true
    }

    private func restyle() {
        // Ghostty's read (owner call 2026-09-10): the selected tab is flush
        // with the app's surface — the panes' base — while the others sit
        // darker (crust) in the mantle row. Three rungs of the z-ramp, the
        // selected one continuous with the content below it.
        let fill: NSColor = isActive ? Theme.Elevation.base : Theme.Elevation.crust
        layer?.backgroundColor = fill.cgColor
        titleLabel.textColor = isActive ? Theme.chromeSelectedText : Theme.chromeText
        // Invisible until the pointer is over the tab (the session tabs'
        // rule); the slot stays reserved so the title never shifts.
        closeButton.alphaValue = hovered ? StripHoverButton.restingAlpha : 0
    }

    private static func makeMark(_ attention: Session.Attention) -> NSView {
        if attention == .needsInput {
            let mark = NSTextField(labelWithString: "!")
            mark.font = Theme.Typography.ui(9, weight: .heavy)
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
        let view = NSView(frame: CGRect(x: 0, y: 0, width: dot, height: dot))
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        view.layer?.cornerRadius = dot / 2
        return view
    }

    override func layout() {
        super.layout()
        // Title and marks sit centered as one group; the `×` keeps its own
        // slot at the trailing edge so the group never shifts on hover.
        let textMax = max(0, bounds.width - 2 * Self.closeSlot - marksWidth)
        let textWidth = min(ceil(titleLabel.fittingSize.width), textMax)
        let textHeight = titleLabel.fittingSize.height
        let group = textWidth + marksWidth
        var x = round((bounds.width - group) / 2)
        titleLabel.frame = CGRect(x: x, y: round((bounds.height - textHeight) / 2), width: textWidth, height: textHeight)
        x += textWidth + Self.markGap
        for view in markViews {
            let size = view.fittingSize == .zero ? CGSize(width: Self.dot, height: Self.dot) : view.fittingSize
            let w = view is NSTextField ? size.width : Self.dot
            let h = view is NSTextField ? size.height : Self.dot
            view.frame = CGRect(x: x, y: round((bounds.height - h) / 2), width: w, height: h)
            x += Self.dot + Self.dotGap
        }
        if !closeButton.isHidden {
            closeButton.frame = CGRect(
                x: bounds.width - 6 - Self.closeWidth,
                y: (bounds.height - Self.closeWidth) / 2,
                width: Self.closeWidth,
                height: Self.closeWidth
            )
        }
    }

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

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        restyle()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        restyle()
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    @objc private func closeTapped() { onClose?() }
}

/// A borderless symbol button that rests dim and brightens under the pointer.
private final class StripHoverButton: NSButton {
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

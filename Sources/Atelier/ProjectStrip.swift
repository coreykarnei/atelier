import AppKit

/// One project tab's display state.
struct ProjectTabInfo {
    let id: ObjectIdentifier
    let title: String
    let isActive: Bool
    /// The attention marks of the project's sessions, in tab order, states
    /// with nothing to say already dropped.
    let marks: [ProjectMark]
}

/// One session's mark on its project tab: the state, and which session it
/// is — a dot is also a way to that session.
struct ProjectMark: Equatable {
    let sessionId: UUID
    let attention: Session.Attention
    let title: String
    let since: Date?
}

/// The project tab row under the titlebar (2026-09-10): Atelier's own tabs,
/// replacing native window tabbing — same shape (a full-width row, tabs
/// dividing it equally, shown once there are two), our material. The
/// active tab is a rounded chip in the panes' base, flush with the content;
/// the others sit darker in crust. Every tab carries its
/// sessions' attention marks after the title (blue working, green done,
/// ringing green unseen completion, peach blocked), so a project you're not
/// looking at still says where its agents stand. `+` opens a new project
/// tab; the active tab's leading `×` closes it — onto the shelf, or with `⌥`
/// held (the `×` goes peach to say so) for good. Gaps pass clicks through to the
/// wash (drag to move, double-click to zoom). Each dot is a way to its
/// session (2026-09-23, owner call): click one and the project comes
/// forward on that session's tab. A tab drags to reorder (2026-09-24,
/// owner call) the way session tabs do: it rides the pointer, and trades
/// places with a neighbour once its leading edge is a little past the
/// neighbour's midpoint.
///
/// Crowding (2026-09-16, owner call): tabs never shrink below `minTabWidth`.
/// Past that the row keeps every tab at that width and runs off the edge —
/// the strip scrolls sideways (trackpad swipe, or a plain wheel turned
/// horizontal) and the clipped edge fades so the overflow is legible at a
/// glance. Selecting a tab (⌘1‥9, ⌃⇥, a click) brings it into view. The
/// earlier `…` overflow menu is gone: it hid projects behind a click and
/// made ⌃⇥ land on tabs you couldn't see.
final class ProjectStripView: NSView {
    var onSelect: ((ObjectIdentifier) -> Void)?
    /// The `×`: this project, and whether `⌥` was held (forget, not shelve).
    var onClose: ((ObjectIdentifier, Bool) -> Void)?
    var onNew: (() -> Void)?
    /// A dot was clicked: this project, this session.
    var onSelectSession: ((ObjectIdentifier, UUID) -> Void)?
    /// A tab was dragged to a new place: the full row order.
    var onReorder: (([ObjectIdentifier]) -> Void)?

    static let rowHeight: CGFloat = 32
    static let tabHeight: CGFloat = 26
    static let gap: CGFloat = 4
    static let plusWidth: CGFloat = 28
    /// A title stays readable; below this the row scrolls instead.
    static let minTabWidth: CGFloat = 180
    /// How far the clipped edge fades into the row.
    private static let edgeFade: CGFloat = 28
    private static let inset: CGFloat = 6

    private var tabs: [ProjectTabView] = []
    private let newButton = HoverPadButton()
    private let scroll = TabRowScrollView()
    private let tabsHost = NSView()
    private let edgeMask = CAGradientLayer()
    private var infos: [ProjectTabInfo] = []
    private var activeId: ObjectIdentifier?
    /// Set while a selection change should scroll the active tab into view
    /// once the next layout has placed it.
    private var revealActiveAfterLayout = false
    /// The tab under the pointer and where on it the press landed.
    private var drag: (id: ObjectIdentifier, grabOffset: CGFloat)?
    /// Each tab's width at the last layout — the slots a drag moves between.
    private var tabWidth: CGFloat = 0
    /// Past a neighbour's midpoint by this much before the two swap — the
    /// session strip's value, so both rows feel the same under the hand.
    private static let swapOvershoot: CGFloat = 6

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        newButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "New project tab")
        newButton.symbolConfiguration = .init(pointSize: 10, weight: .medium)
        newButton.contentTintColor = Theme.chromeMutedText
        newButton.alphaValue = HoverPadButton.restingAlpha
        newButton.toolTip = "New Project Tab  ⌘T"
        newButton.target = self
        newButton.action = #selector(newTapped)
        addSubview(newButton)

        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .automatic
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.documentView = tabsHost
        scroll.wantsLayer = true
        edgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        addSubview(scroll)
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Gaps belong to the titlebar (window drag / double-click zoom), not to
    /// the strip — and not to the scroll view's own chrome either.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit === self || hit === scroll || hit === scroll.contentView || hit === tabsHost { return nil }
        return hit
    }

    func update(tabs infos: [ProjectTabInfo]) {
        var infos = infos
        if drag != nil {
            // Mid-drag the row's order is the pointer's, not the owner's
            // (attention changes refresh the strip at any moment).
            let rank = Dictionary(uniqueKeysWithValues: tabs.enumerated().map { ($1.id, $0) })
            infos.sort { (rank[$0.id] ?? .max) < (rank[$1.id] ?? .max) }
        }
        self.infos = infos
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
        let active = infos.first(where: { $0.isActive })?.id
        if active != activeId {
            activeId = active
            revealActiveAfterLayout = true
        }
        needsLayout = true
    }

    private func makeTab(id: ObjectIdentifier) -> ProjectTabView {
        let tab = ProjectTabView(id: id)
        tab.onSelect = { [weak self] in self?.onSelect?(id) }
        tab.onClose = { [weak self] forget in self?.onClose?(id, forget) }
        tab.onSelectSession = { [weak self] session in self?.onSelectSession?(id, session) }
        tab.onDragBegan = { [weak self] tab, event in self?.dragBegan(tab, event) }
        tab.onDragMoved = { [weak self] tab, event in self?.dragMoved(tab, event) }
        tab.onDragEnded = { [weak self] tab in self?.dragEnded(tab) }
        tabsHost.addSubview(tab)
        return tab
    }

    override func layout() {
        super.layout()
        newButton.frame = CGRect(x: bounds.width - Self.plusWidth, y: (bounds.height - Self.plusWidth) / 2,
                                 width: Self.plusWidth, height: Self.plusWidth)
        let viewport = CGRect(x: 0, y: 0, width: max(0, bounds.width - Self.plusWidth), height: bounds.height)
        scroll.frame = viewport

        // Equal shares of the row while they fit; the floor width, run off
        // the edge, once they don't.
        let count = CGFloat(tabs.count)
        let available = viewport.width - 2 * Self.inset - Self.gap * max(0, count - 1)
        let share = count > 0 ? floor(available / count) : 0
        tabWidth = max(Self.minTabWidth, share)
        let contentWidth = count > 0 ? 2 * Self.inset + count * tabWidth + Self.gap * (count - 1) : 0
        tabsHost.frame = CGRect(x: 0, y: 0, width: max(viewport.width, contentWidth), height: viewport.height)
        placeTabs(animated: false)

        // Layout can shrink the content under a scrolled clip; keep the
        // origin inside the document.
        let maxOrigin = max(0, tabsHost.frame.width - viewport.width)
        if scroll.contentView.bounds.origin.x > maxOrigin {
            scroll.contentView.setBoundsOrigin(NSPoint(x: maxOrigin, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        if revealActiveAfterLayout {
            revealActiveAfterLayout = false
            revealActive()
        }
        updateEdgeFade()
    }

    /// The frame of the `index`th slot in the row.
    private func slot(_ index: Int) -> CGRect {
        CGRect(
            x: Self.inset + CGFloat(index) * (tabWidth + Self.gap),
            y: (tabsHost.bounds.height - Self.tabHeight) / 2,
            width: tabWidth,
            height: Self.tabHeight
        )
    }

    /// Every tab to its slot — except the one riding the pointer.
    private func placeTabs(animated: Bool) {
        let moving = tabs.enumerated().filter { $0.element.id != drag?.id }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            for (index, tab) in moving { tab.frame = slot(index) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for (index, tab) in moving { tab.animator().frame = slot(index) }
        }
    }

    // MARK: Drag to reorder

    private func dragBegan(_ tab: ProjectTabView, _ event: NSEvent) {
        let point = tabsHost.convert(event.locationInWindow, from: nil)
        drag = (tab.id, point.x - tab.frame.minX)
        // Above its neighbours while it travels.
        tabsHost.addSubview(tab)
        tab.shadow = Theme.Elevation.raisedShadow
    }

    private func dragMoved(_ tab: ProjectTabView, _ event: NSEvent) {
        guard let drag, drag.id == tab.id, let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let point = tabsHost.convert(event.locationInWindow, from: nil)
        tab.frame.origin.x = min(max(point.x - drag.grabOffset, 0), tabsHost.bounds.width - tab.frame.width)
        // One step at a time, measured against the neighbours' *slots* (their
        // frames may still be gliding from the last swap).
        var target = index
        if index > 0, tab.frame.minX < slot(index - 1).midX - Self.swapOvershoot {
            target = index - 1
        } else if index + 1 < tabs.count, tab.frame.maxX > slot(index + 1).midX + Self.swapOvershoot {
            target = index + 1
        }
        guard target != index else { return }
        tabs.swapAt(index, target)
        placeTabs(animated: true)
    }

    private func dragEnded(_ tab: ProjectTabView) {
        guard drag?.id == tab.id else { return }
        drag = nil
        tab.shadow = nil
        placeTabs(animated: true)
        onReorder?(tabs.map(\.id))
    }

    /// Scroll the active tab fully into the viewport (nearest edge), with a
    /// short glide unless the row is already showing it.
    private func revealActive() {
        guard let activeId, let tab = tabs.first(where: { $0.id == activeId }) else { return }
        let clip = scroll.contentView
        let visible = clip.bounds
        var target = visible.origin.x
        if tab.frame.minX - Self.inset < visible.minX {
            target = tab.frame.minX - Self.inset
        } else if tab.frame.maxX + Self.inset > visible.maxX {
            target = tab.frame.maxX + Self.inset - visible.width
        }
        target = min(max(0, target), max(0, tabsHost.frame.width - visible.width))
        guard target != visible.origin.x else { return }
        let origin = NSPoint(x: target, y: 0)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            clip.setBoundsOrigin(origin)
            scroll.reflectScrolledClipView(clip)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(origin)
        }
    }

    @objc private func scrolled() { updateEdgeFade() }

    /// The clipped edges fade into the row so a cut-off tab reads as "more
    /// this way", not as a broken layout. Whole row opaque when it fits.
    private func updateEdgeFade() {
        let clip = scroll.contentView
        let width = clip.bounds.width
        guard width > 0, tabsHost.frame.width > width + 0.5 else {
            scroll.layer?.mask = nil
            return
        }
        let canLeft = clip.bounds.origin.x > 0.5
        let canRight = clip.bounds.maxX < tabsHost.frame.width - 0.5
        let fade = Self.edgeFade / width
        edgeMask.frame = scroll.bounds
        edgeMask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        let solid = NSColor.black.cgColor
        let clear = NSColor.clear.cgColor
        edgeMask.colors = [canLeft ? clear : solid, solid, solid, canRight ? clear : solid]
        if scroll.layer?.mask !== edgeMask { scroll.layer?.mask = edgeMask }
    }

    @objc private func newTapped() { onNew?() }
}

/// The row's scroll view: a plain wheel (mouse, or two fingers straight
/// up/down) turns sideways — the row has no vertical axis to spend it on —
/// while a real horizontal swipe keeps AppKit's own momentum and rubber
/// band.
private final class TabRowScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard abs(dy) > abs(dx), let document = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let clip = contentView
        let maxOrigin = max(0, document.frame.width - clip.bounds.width)
        guard maxOrigin > 0 else { return }
        let step = event.hasPreciseScrollingDeltas ? dy : dy * 10
        let x = min(max(0, clip.bounds.origin.x - step), maxOrigin)
        clip.setBoundsOrigin(NSPoint(x: x, y: 0))
        reflectScrolledClipView(clip)
    }
}

/// A single project tab: title and the sessions' marks centered, the `×` at
/// the leading edge of the active tab (revealed on hover; the group is
/// centered against symmetric slots so nothing shifts).
private final class ProjectTabView: NSView {
    let id: ObjectIdentifier
    var onSelect: (() -> Void)?
    var onClose: ((_ forget: Bool) -> Void)?
    var onSelectSession: ((UUID) -> Void)?
    var onDragBegan: ((ProjectTabView, NSEvent) -> Void)?
    var onDragMoved: ((ProjectTabView, NSEvent) -> Void)?
    var onDragEnded: ((ProjectTabView) -> Void)?
    private var pressLocation: NSPoint?
    private var isDragging = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = HoverPadButton()
    private var markViews: [MarkButton] = []
    private var marks: [ProjectMark] = []
    private var isActive = false
    private var hovered = false
    private var tracking: NSTrackingArea?
    /// `⌥` held over the tab: the `×` becomes the close that keeps nothing.
    private var optionHeld = false
    private var flagsMonitor: Any?

    private static let closeWidth: CGFloat = 16
    private static let closeSlot: CGFloat = 6 + 16 + 6
    private static let markGap: CGFloat = 6
    /// A touch larger than the session tabs' 6pt (2026-09-23): these dots
    /// are click targets now, and they sit in a quieter row.
    private static let dot: CGFloat = 7
    private static let dotGap: CGFloat = 5

    override var mouseDownCanMoveWindow: Bool { false }

    init(id: ObjectIdentifier) {
        self.id = id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusMedium

        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = Theme.Typography.mono(Theme.Typography.body, weight: .medium)
        addSubview(titleLabel)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close project")
        closeButton.symbolConfiguration = .init(pointSize: 8, weight: .medium)
        closeButton.contentTintColor = Theme.chromeText
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        closeButton.alphaValue = 0
        addSubview(closeButton)
        installTracking()
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
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(info.title)
        setAccessibilityValue(isActive ? 1 : 0)
        closeButton.toolTip = "Close Project  ⌥⌘W\n⌥-click ends its sessions"
        closeButton.isHidden = !isActive
        toolTip = info.title
        let identity = { (marks: [ProjectMark]) in marks.map { "\($0.sessionId)\($0.attention)" } }
        if identity(info.marks) != identity(marks) {
            // Rebuild only when a dot's session or state changes — the bar
            // refreshes often, and a rebuilt dot restarts its motion.
            for view in markViews { view.removeFromSuperview() }
            markViews = info.marks.map { mark in
                let view = MarkButton(mark: mark, diameter: Self.dot)
                view.onPress = { [weak self] in self?.onSelectSession?(mark.sessionId) }
                addSubview(view)
                return view
            }
        } else {
            // Titles and timestamps move without a rebuild.
            for (view, mark) in zip(markViews, info.marks) { view.mark = mark }
        }
        marks = info.marks
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
        closeButton.alphaValue = hovered ? HoverPadButton.restingAlpha : 0
        closeButton.contentTintColor = optionHeld ? Theme.accentPeach : Theme.chromeText
        closeButton.setAccessibilityLabel(optionHeld ? "Close project and end sessions" : "Close project")
    }

    /// Watch `⌥` only while the pointer is over the tab — the one place the
    /// modifier changes what a click does.
    private func setOptionHeld(_ held: Bool) {
        guard held != optionHeld else { return }
        optionHeld = held
        restyle()
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
        // Each dot's target spans half the gap either side and the tab's
        // full height; the dot itself stays on the title's centre line.
        for view in markViews {
            view.frame = CGRect(x: x - Self.dotGap / 2, y: 0, width: Self.dot + Self.dotGap, height: bounds.height)
            x += Self.dot + Self.dotGap
        }
        if !closeButton.isHidden {
            // Leading, where macOS puts a tab's close (owner call 2026-09-10).
            closeButton.frame = CGRect(
                x: 6,
                y: (bounds.height - Self.closeWidth) / 2,
                width: Self.closeWidth,
                height: Self.closeWidth
            )
        }
    }

    /// Installed at init: AppKit only asks a view to update tracking areas
    /// once it has one. `.inVisibleRect` keeps the rect on the view's bounds
    /// as tabs re-share the row.
    private func installTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        optionHeld = event.modifierFlags.contains(.option)
        restyle()
        if flagsMonitor == nil {
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.setOptionHeld(event.modifierFlags.contains(.option))
                return event
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        optionHeld = false
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        restyle()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
        pressLocation = event.locationInWindow
        isDragging = false
    }

    /// A few points of travel turns the press into a drag, as on a session tab.
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

    override func accessibilityPerformPress() -> Bool { onSelect?(); return true }

    @objc private func closeTapped() {
        onClose?(NSApp.currentEvent?.modifierFlags.contains(.option) ?? false)
    }
}

/// A project tab's attention dot as a target (2026-09-23, owner call): the
/// pointing hand over it, the strip's hover pad behind it (HoverPadButton's
/// fills, on a circle the dot's own shape), and a click — press and release
/// inside, as a button — shows its session. It never selects the tab under
/// it by accident: the press stops here.
private final class MarkButton: NSView {
    var mark: ProjectMark {
        didSet { setAccessibilityLabel(Self.accessibilityText(mark)) }
    }
    var onPress: (() -> Void)?

    private let dotView: AttentionDotView
    private let padLayer = CALayer()
    private let diameter: CGFloat
    private var hovered = false
    private var pressed = false

    /// The pad a hovered dot sits in.
    private static let pad: CGFloat = 15

    override var mouseDownCanMoveWindow: Bool { false }

    init(mark: ProjectMark, diameter: CGFloat) {
        self.mark = mark
        self.diameter = diameter
        dotView = AttentionDotView(attention: mark.attention, diameter: diameter)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        padLayer.cornerRadius = Self.pad / 2
        padLayer.bounds = CGRect(x: 0, y: 0, width: Self.pad, height: Self.pad)
        layer?.addSublayer(padLayer)
        addSubview(dotView)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(Self.accessibilityText(mark))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func accessibilityText(_ mark: ProjectMark) -> String {
        "\(mark.title), \(AttentionTip.line(mark.attention, since: nil))"
    }

    override func layout() {
        super.layout()
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        dotView.frame = CGRect(x: round(center.x - diameter / 2), y: round(center.y - diameter / 2),
                               width: diameter, height: diameter)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        padLayer.position = CGPoint(x: dotView.frame.midX, y: dotView.frame.midY)
        CATransaction.commit()
        // Re-registered only when the rect moves: tearing the tip down each
        // pass resets its hover timer, and it would never show.
        if bounds != tipRect {
            tipRect = bounds
            removeAllToolTips()
            addToolTip(bounds, owner: self, userData: nil)
        }
    }

    private var tipRect: CGRect = .null

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; refreshPad() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshPad() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; pressed = false; refreshPad() }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        refreshPad()
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        guard inside != pressed else { return }
        pressed = inside
        refreshPad()
    }

    override func mouseUp(with event: NSEvent) {
        let fire = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        refreshPad()
        if fire { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool { onPress?(); return true }

    private func refreshPad() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        padLayer.backgroundColor = hovered || pressed
            ? NSColor.white.withAlphaComponent(pressed ? 0.26 : 0.16).cgColor : nil
        CATransaction.commit()
    }

    /// `Atelier checkout flow — waiting · 4m`: which session, and the one
    /// line the dots everywhere answer (§4, time on inquiry).
    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData: UnsafeMutableRawPointer?) -> String {
        "\(mark.title) — \(AttentionTip.line(mark.attention, since: mark.since))"
    }
}

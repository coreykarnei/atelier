import AppKit

/// Shared physiology for the floating overlays (POLISH_PLAN §6) — the palette,
/// the `⌘P` picker, `⌘⇧F`, and the worktree chooser.

/// One sliding rounded-rect selection highlight: a single view that glides
/// between rows (~120 ms) instead of discrete row repaints. The table's own
/// selection drawing is disabled; selection *state* still lives in the table.
final class SlidingSelectionHighlight {
    private let view = NSView()

    init() {
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.Elevation.surface0.cgColor
        view.layer?.cornerRadius = Theme.Elevation.radiusMedium
        view.isHidden = true
    }

    func attach(to table: NSTableView) {
        table.selectionHighlightStyle = .none
        table.addSubview(view, positioned: .below, relativeTo: nil)
    }

    /// Move the highlight to the table's current selection. Animated for
    /// within-list moves (arrows); instant after refilters, where the row set
    /// itself changed and a glide would lie about continuity.
    func update(for table: NSTableView, animated: Bool) {
        let row = table.selectedRow
        guard row >= 0, row < table.numberOfRows else {
            view.isHidden = true
            return
        }
        let rect = table.rect(ofRow: row).insetBy(dx: 4, dy: 1)
        guard !rect.isEmpty else {
            view.isHidden = true
            return
        }
        let wasHidden = view.isHidden
        view.isHidden = false
        if animated && !wasHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                view.animator().frame = rect
            }
        } else {
            view.frame = rect
        }
    }
}

/// The floating summon card (POLISH_PLAN §6 physiology, extracted for M2.2):
/// scrim, hud-blur card descending from the titlebar, top hairline, and a
/// SummonList whose height the card hugs as you type. The command palette and
/// the `⌘P` file picker are both this overlay with different offers.
class SummonCardOverlay: NSView {
    let summon: SummonList
    private let onDismissHandler: () -> Void

    /// Carries the floating shadow; the card itself masks to its rounded
    /// corners, which would clip a shadow set on its own layer.
    private let cardHost = NSView()
    private let card = OverlayMaterialView()
    private var listHeight: NSLayoutConstraint?
    private var cardWidth: NSLayoutConstraint?
    private let maxListHeight: CGFloat

    init(summonStyle: SummonList.Style, maxListHeight: CGFloat = 300, onDismiss: @escaping () -> Void) {
        self.summon = SummonList(style: summonStyle)
        self.maxListHeight = maxListHeight
        self.onDismissHandler = onDismiss
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

        summon.translatesAutoresizingMaskIntoConstraints = false
        summon.onEscape = { [weak self] in self?.dismiss() }
        summon.onContentChange = { [weak self] in self?.trackContentHeight() }
        card.addSubview(summon)

        let width = cardHost.widthAnchor.constraint(equalToConstant: 560)
        cardWidth = width
        NSLayoutConstraint.activate([
            cardHost.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            width,

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            summon.topAnchor.constraint(equalTo: card.topAnchor),
            summon.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            summon.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            summon.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        let height = summon.makeListHeightConstraint(constant: min(summon.contentHeight, maxListHeight))
        height.isActive = true
        listHeight = height
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cardWidth?.constant = min(560, max(0, newSize.width - 32))
        listHeight?.constant = min(summon.contentHeight, availableListHeight)
    }

    private var availableListHeight: CGFloat {
        bounds.height > 0 ? min(maxListHeight, max(28, bounds.height - 76)) : maxListHeight
    }

    func dismiss() { onDismissHandler() }

    /// The panel height tracks the results as you type (§6 — the single
    /// biggest "native" tell).
    private func trackContentHeight() {
        let newHeight = min(summon.contentHeight, availableListHeight)
        guard let listHeight, listHeight.constant != newHeight else { return }
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
    var focusField: NSView { summon.focusField }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !cardHost.frame.contains(point) { dismiss() }
    }
}

/// A keycap chip (Theme.Typography.Keycap): mono glyphs on a surface0 fill,
/// 4 pt radius, hairline top edge — obeying the lighting model.
final class KeycapChipView: NSView {
    private let label: NSTextField

    init(chord: String) {
        label = NSTextField(labelWithString: chord)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.Typography.Keycap.fill.cgColor
        layer?.cornerRadius = Theme.Typography.Keycap.radius

        label.font = Theme.Typography.Keycap.font
        label.textColor = Theme.chromeText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        let topEdge = NSView()
        topEdge.wantsLayer = true
        topEdge.layer?.backgroundColor = Theme.Typography.Keycap.topEdge.cgColor
        topEdge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topEdge)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            topEdge.topAnchor.constraint(equalTo: topAnchor),
            topEdge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Typography.Keycap.radius),
            topEdge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Typography.Keycap.radius),
            topEdge.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// One material for transient surfaces. The neutral wash keeps HUD vibrancy
/// from making the chooser and palette look like unrelated stock panels.
final class OverlayMaterialView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        NSWorkspace.shared.notificationCenter.addObserver(self,
            selector: #selector(refreshMaterial),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        refreshMaterial()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func refreshMaterial() {
        layer?.backgroundColor = Theme.Elevation.overlayFill.withAlphaComponent(
            NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.78).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = Theme.Elevation.hairline.cgColor
    }
}

/// Consistent hover, press and disabled states for layer-drawn overlay buttons.
class OverlayActionButton: NSButton {
    private var hovered = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil))
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4; refresh() } }
    override func mouseEntered(with event: NSEvent) { hovered = true; refresh() }
    override func mouseExited(with event: NSEvent) { hovered = false; refresh() }
    override func highlight(_ flag: Bool) { super.highlight(flag); refresh() }
    private func refresh() {
        layer?.backgroundColor = (isEnabled && (hovered || isHighlighted)
            ? Theme.Elevation.surface1 : Theme.Elevation.surface0).cgColor
        layer?.borderWidth = isHighlighted ? 1 : 0
        layer?.borderColor = Theme.chromeMutedText.withAlphaComponent(0.4).cgColor
    }
}

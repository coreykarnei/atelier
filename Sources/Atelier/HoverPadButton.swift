import AppKit

/// A borderless symbol button (`×`, `+`) that answers hover with a soft
/// rounded pad behind the glyph rather than brightening it — the macOS tab
/// close's manner (owner call 2026-09-10). The glyph rests dim and stays
/// dim; the pad says "this is a button" without the glyph shouting.
final class HoverPadButton: NSButton {
    static let restingAlpha: CGFloat = 0.55
    /// The pad's colour; hosts on a dark fill use a light pad and vice versa.
    var hoverFill: NSColor = NSColor.white.withAlphaComponent(0.10)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Theme.Elevation.radiusSmall
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        // Installed at init: AppKit only asks a view to update tracking
        // areas once it has one; .inVisibleRect follows the frame.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var hovered = false
    override var isEnabled: Bool { didSet { refreshPad() } }
    override func mouseEntered(with event: NSEvent) { hovered = true; refreshPad() }
    override func mouseExited(with event: NSEvent) { hovered = false; refreshPad() }
    override func highlight(_ flag: Bool) { super.highlight(flag); refreshPad() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); hovered = false; refreshPad() }
    private func refreshPad() {
        layer?.backgroundColor = isEnabled && (hovered || isHighlighted)
            ? hoverFill.withAlphaComponent(isHighlighted ? 0.18 : 0.10).cgColor : nil
    }
}

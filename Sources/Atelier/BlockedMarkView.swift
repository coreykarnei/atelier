import AppKit

/// The *blocked* attention mark (§7.1 peach `!`), drawn rather than typed:
/// a filled peach disc with the `!` cut into it in the chrome's darkest
/// tone. Sits in a row of dots as one of them, a size up — a text `!` next
/// to dots read as a stray character (owner note 2026-09-15). Deliberately
/// inanimate (§1.3).
final class BlockedMarkView: NSView {
    private let diameter: CGFloat

    init(diameter: CGFloat) {
        self.diameter = diameter
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize { NSSize(width: diameter, height: diameter) }
    override var intrinsicContentSize: NSSize { fittingSize }

    override func draw(_ dirtyRect: NSRect) { Self.draw(in: bounds) }

    /// The mark, drawn into the largest disc `bounds` holds (also the menu
    /// image path, which has no view).
    static func draw(in bounds: CGRect) {
        let d = min(bounds.width, bounds.height)
        let disc = CGRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        Theme.accentPeach.setFill()
        NSBezierPath(ovalIn: disc).fill()

        // The `!`: a rounded stem over a dot, both in the row's dark ground so
        // the mark stays one colour from a distance and a glyph up close.
        Theme.Elevation.crust.setFill()
        let stemW = max(1.5, d * 0.16)
        let dotD = max(1.5, d * 0.18)
        let cx = disc.midX
        let top = disc.maxY - d * 0.22
        let dotY = disc.minY + d * 0.2
        let stemBottom = dotY + dotD + d * 0.1
        NSBezierPath(roundedRect: CGRect(x: cx - stemW / 2, y: stemBottom, width: stemW, height: top - stemBottom),
                     xRadius: stemW / 2, yRadius: stemW / 2).fill()
        NSBezierPath(ovalIn: CGRect(x: cx - dotD / 2, y: dotY, width: dotD, height: dotD)).fill()
    }
}

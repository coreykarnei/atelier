import AppKit

/// The attention palette (§7.1, revised 2026-09-15): three colours, three
/// meanings. Blue — the agent is busy. Green — its turn is done and it's
/// your move (whether or not you've looked yet; the *unseen* case pulses
/// instead of changing hue). Peach — blocked on you, a permission or a
/// question, and the only orange on screen, so orange keeps meaning
/// "needs you" rather than "everyone finished".
extension Theme {
    static func attentionColor(_ attention: Session.Attention) -> NSColor {
        switch attention {
        case .working: return accentBlue
        case .waiting, .doneUnseen: return accentGreen
        case .needsInput, .none: return accentPeach
        }
    }
}

/// A round attention dot drawn as a centered sublayer (so scale animations
/// grow from the middle), with its state's motion installed once the layer
/// joins a window — animations added earlier are dropped by AppKit.
/// Working: the ~4 s subliminal pulse (§1.1 item 4). Unseen completion: a
/// clear ~1.2 s pulse — the one state that wants your eye, so it moves
/// (owner call 2026-09-15). Everything else is still (§1.3).
final class AttentionDotView: NSView {
    let dotLayer = CALayer()
    private let attention: Session.Attention
    private let diameter: CGFloat

    init(attention: Session.Attention, diameter: CGFloat) {
        self.attention = attention
        self.diameter = diameter
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        dotLayer.backgroundColor = Theme.attentionColor(attention).cgColor
        dotLayer.cornerRadius = diameter / 2
        dotLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dotLayer.position = CGPoint(x: diameter / 2, y: diameter / 2)
        layer?.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize { NSSize(width: diameter, height: diameter) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              dotLayer.animation(forKey: "pulse") == nil else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        switch attention {
        case .working:
            pulse.fromValue = 1.0; pulse.toValue = 0.8; pulse.duration = 2.0
        case .doneUnseen:
            pulse.fromValue = 1.0; pulse.toValue = 0.25; pulse.duration = 0.6
        case .waiting, .needsInput, .none:
            return
        }
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(pulse, forKey: "pulse")
    }
}

/// The *blocked* mark (peach `!`), drawn rather than typed:
/// a filled peach disc with the `!` cut into it in the chrome's darkest
/// tone. Sits in a row of dots as one of them, a size up — a text `!` next
/// to dots read as a stray character (owner note 2026-09-15); a hair, not a
/// size, above them. Deliberately
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

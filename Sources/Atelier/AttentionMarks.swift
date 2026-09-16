import AppKit

/// The attention palette (§7.1, revised 2026-09-15): three colours, three
/// meanings. Blue — the agent is busy. Green — its turn is done and it's
/// your move (whether or not you've looked yet; the *unseen* case pulses
/// instead of changing hue). Peach — blocked on you, a permission or a
/// question, and the only orange on screen, so orange keeps meaning
/// "needs you" rather than "everyone finished". With one state per hue
/// every mark is a plain dot; the `!` went (owner call 2026-09-15).
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

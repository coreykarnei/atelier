import AppKit

/// The attention palette (§7.1, revised 2026-09-15): three colours, three
/// meanings. Blue — the agent is busy. Green — its turn is done and it's
/// your move. Peach — blocked on you, a permission or a question, and the
/// only orange on screen, so orange keeps meaning "needs you" rather than
/// "everyone finished". Whether you've looked yet never changes the hue:
/// the *unseen* green and peach ring instead (2026-09-23). With one meaning
/// per hue every mark is a plain dot; the `!` went (owner call 2026-09-15).
extension Theme {
    static func attentionColor(_ attention: Session.Attention) -> NSColor {
        switch attention {
        case .working: return accentBlue
        case .waiting, .doneUnseen: return accentGreen
        case .needsInput, .needsInputUnseen, .none: return accentPeach
        }
    }
}

/// The one muted line an attention dot answers on hover — `waiting · 4m` —
/// computed when asked, never shown unasked (§1.3).
enum AttentionTip {
    static func line(_ attention: Session.Attention, since: Date?) -> String {
        let word: String
        switch attention {
        case .working: word = "working"
        case .waiting: word = "waiting"
        case .needsInput, .needsInputUnseen: word = "blocked"
        case .doneUnseen: word = "done"
        case .none: return ""
        }
        guard let since else { return word }
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

/// A round attention dot drawn as a centered sublayer (so scale animations
/// grow from the middle), with its state's motion installed once the layer
/// joins a window — animations added earlier are dropped by AppKit.
/// Working: the ~4 s subliminal pulse (§1.1 item 4). Unseen — a completion
/// or a block that landed while you were elsewhere — is what wants your eye,
/// so it moves (owner calls 2026-09-15, 2026-09-23): the dot holds steady
/// and a hairline ring in its colour leaves it, widening and fading, once
/// every beat. A ring reads as "something happened here" where a blinking
/// dot read as a fault. Same beat forever — the ring never grows louder
/// with age (§1.3). Once seen, every mark is still; a seen peach block
/// stays still by rule ("urgency reads as stillness").
final class AttentionDotView: NSView {
    let dotLayer = CALayer()
    private let ringLayer = CALayer()
    private let attention: Session.Attention
    private let diameter: CGFloat

    /// How far the ring travels: its final diameter, as a multiple of the dot.
    private static let ringReach: CGFloat = 2.2
    /// One ring per beat: it spreads over `ringTravel`, then the dot rests.
    private static let ringBeat: CFTimeInterval = 2.0
    private static let ringTravel: CFTimeInterval = 1.3

    init(attention: Session.Attention, diameter: CGFloat) {
        self.attention = attention
        self.diameter = diameter
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        // The ring spreads past the view's frame; nothing here may clip it.
        layer?.masksToBounds = false
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let color = Theme.attentionColor(attention).cgColor
        if attention.isUnseen {
            // Under the dot, so the ring is born from its edge. A border
            // over a clear fill, with bounds (not scale) animated, keeps the
            // stroke a hairline at every size.
            ringLayer.borderColor = color
            ringLayer.borderWidth = 1
            ringLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            ringLayer.cornerRadius = diameter / 2
            ringLayer.position = center
            ringLayer.opacity = 0
            layer?.addSublayer(ringLayer)
        }
        dotLayer.backgroundColor = color
        dotLayer.cornerRadius = diameter / 2
        dotLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        dotLayer.position = center
        layer?.addSublayer(dotLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var fittingSize: NSSize { NSSize(width: diameter, height: diameter) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        switch attention {
        case .working:
            guard !reduceMotion, dotLayer.animation(forKey: "pulse") == nil else { return }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0; pulse.toValue = 0.8; pulse.duration = 2.0
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dotLayer.add(pulse, forKey: "pulse")
        case .doneUnseen, .needsInputUnseen:
            if reduceMotion {
                // The ring held still, halfway out — the state stays
                // distinct from a plain waiting dot without moving.
                let size = diameter * (1 + Self.ringReach) / 2
                ringLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
                ringLayer.cornerRadius = size / 2
                ringLayer.opacity = 0.45
                return
            }
            guard ringLayer.animation(forKey: "ring") == nil else { return }
            let ring = Self.ringAnimation(diameter: diameter)
            // Phase-locked to one app-wide beat: every unseen dot, wherever
            // it is and whenever it arrived, rings on the same count — a
            // row of them reads as one signal, not a scatter.
            let now = CACurrentMediaTime()
            ring.beginTime = ringLayer.convertTime(now - fmod(now, Self.ringBeat), from: nil)
            ringLayer.add(ring, forKey: "ring")
        case .waiting, .needsInput, .none:
            return
        }
    }

    private static func ringAnimation(diameter: CGFloat) -> CAAnimation {
        let reach = diameter * ringReach
        let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1)
        let size = CABasicAnimation(keyPath: "bounds.size")
        size.fromValue = NSValue(size: NSSize(width: diameter, height: diameter))
        size.toValue = NSValue(size: NSSize(width: reach, height: reach))
        let radius = CABasicAnimation(keyPath: "cornerRadius")
        radius.fromValue = diameter / 2
        radius.toValue = reach / 2
        for animation in [size, radius] {
            animation.duration = ringTravel
            animation.timingFunction = easeOut
        }
        // Visible from the start, gone before it stops growing: the ring
        // dissolves while still moving, so no frame shows it parked.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.75, 0.45, 0]
        fade.keyTimes = [0, 0.35, 1]
        fade.duration = ringTravel
        let beat = CAAnimationGroup()
        beat.animations = [size, radius, fade]
        beat.duration = ringBeat
        beat.repeatCount = .infinity
        return beat
    }
}

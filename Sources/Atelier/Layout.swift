import AppKit

/// The two fixed layout modes (MILESTONE_1 §3). Not arbitrary splits — exactly
/// these two, which keeps the workspace on the right side of "not a general
/// multiplexer."
///
/// - `triptych`: editor top-left, shell bottom-left, agent right.
/// - `split`: agent top, shell bottom, full width; editor hidden (state preserved).
enum LayoutMode: String {
    case triptych
    case split

    var next: LayoutMode { self == .triptych ? .split : .triptych }
}

/// A resizable divider whose position persists across restarts.
///
/// Stepping stone: persisted globally per (mode, slot) in `UserDefaults` for
/// Milestone 1.1, since there is only one implicit session. M1.2 re-keys this by
/// session id so each tab owns its own dividers (MILESTONE_1 §3: "per-session is
/// the only truth"). The fraction is stored 0–1 so it survives window resizing.
struct LayoutSlot {
    let key: String
    let defaultFraction: CGFloat
    /// Minimum point size of the first (top/left) subview.
    let minFirst: CGFloat
    /// Minimum point size of the second (bottom/right) subview.
    let minSecond: CGFloat

    var fraction: CGFloat {
        get {
            guard let stored = UserDefaults.standard.object(forKey: key) as? Double else {
                return defaultFraction
            }
            return CGFloat(stored)
        }
        nonmutating set {
            UserDefaults.standard.set(Double(newValue), forKey: key)
        }
    }
}

enum LayoutSlots {
    /// Triptych outer split: left column width vs. agent (vertical divider).
    static let triptychOuter = LayoutSlot(key: "layout.triptych.outer", defaultFraction: 0.47, minFirst: 280, minSecond: 360)
    /// Triptych inner split: editor height vs. shell (horizontal divider).
    static let triptychInner = LayoutSlot(key: "layout.triptych.inner", defaultFraction: 0.70, minFirst: 120, minSecond: 80)
    /// Split mode: agent height vs. shell (horizontal divider). Agent takes the
    /// larger share — in this mode you're driving the agent, the shell is a sidecar.
    static let splitVertical = LayoutSlot(key: "layout.split.vertical", defaultFraction: 0.75, minFirst: 160, minSecond: 80)
}

/// An `NSSplitView` that knows which persisted slot governs its divider, so the
/// window controller can save/restore and constrain it without tracking identity
/// separately.
final class LayoutSplitView: NSSplitView {
    var slot: LayoutSlot!
}

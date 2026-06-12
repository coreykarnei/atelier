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

/// Static configuration for one resizable divider: its identity, default position,
/// and the minimum sizes of the two subviews it separates.
///
/// The *actual* position is owned per-session (M1.2): each `Session` stores its own
/// fraction keyed by `(mode, slot.id)`, so two tabs on the same root keep
/// independent dividers (MILESTONE_1 §3: "per-session is the only truth"). M1.5
/// serializes those to disk; until then they live in memory on the session.
struct LayoutSlot {
    let id: String
    let defaultFraction: CGFloat
    /// Minimum point size of the first (top/left) subview.
    let minFirst: CGFloat
    /// Minimum point size of the second (bottom/right) subview.
    let minSecond: CGFloat
}

enum LayoutSlots {
    /// Triptych outer split: left column width vs. agent (vertical divider).
    static let triptychOuter = LayoutSlot(id: "triptych.outer", defaultFraction: 0.47, minFirst: 280, minSecond: 360)
    /// Triptych inner split: editor height vs. shell (horizontal divider).
    static let triptychInner = LayoutSlot(id: "triptych.inner", defaultFraction: 0.70, minFirst: 120, minSecond: 80)
    /// Split mode: agent height vs. shell (horizontal divider). Agent takes the
    /// larger share — in this mode you're driving the agent, the shell is a sidecar.
    static let splitVertical = LayoutSlot(id: "split.vertical", defaultFraction: 0.75, minFirst: 160, minSecond: 80)
    /// Landing: recents list height vs. terminal (horizontal divider).
    static let landingVertical = LayoutSlot(id: "landing.vertical", defaultFraction: 0.32, minFirst: 110, minSecond: 120)
}

/// An `NSSplitView` that knows which slot governs its divider, so the owning session
/// can save/restore and constrain it without tracking identity separately.
final class LayoutSplitView: NSSplitView {
    var slot: LayoutSlot!

    /// Brackets a divider drag: `true` on mouse-down, `false` when the drag's
    /// tracking loop returns. The session freezes terminal PTY resizes between
    /// the two (§1.5: PTY resize is debounced to drag-end).
    var onDividerDrag: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        // NSSplitView runs the entire divider-drag tracking loop synchronously
        // inside mouseDown, so this brackets exactly one drag. Subview clicks
        // never reach here (the panes swallow them).
        onDividerDrag?(true)
        super.mouseDown(with: event)
        onDividerDrag?(false)
    }
}

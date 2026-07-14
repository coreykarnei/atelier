import AppKit

/// The fixed layout modes (MILESTONE_1 §3). Not arbitrary splits — exactly
/// these, which keeps the workspace on the right side of "not a general
/// multiplexer."
///
/// - `triptych`: editor top-left, shell bottom-left, agent right.
/// - `split`: agent top, shell bottom, full width; editor hidden (state preserved).
/// - `splitSide`: shell left, agent right — the two-pane echo of the ide
///   script's anatomy. Remote sessions (which never show the editor) toggle
///   `split ↔ splitSide` on ⌘\; the local cycle stays `triptych ↔ split`.
enum LayoutMode: String {
    case triptych
    case split
    case splitSide

    /// The local ⌘\ cycle. `splitSide` isn't in it (it exits to triptych if
    /// a local session ever lands there).
    var next: LayoutMode { self == .triptych ? .split : .triptych }

    /// The two-pane ⌘\ cycle: stacked ↔ side-by-side.
    var nextSplit: LayoutMode { self == .split ? .splitSide : .split }
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
    /// Side-by-side split: shell width vs. agent (vertical divider). Mirrors
    /// the triptych outer proportions — the agent keeps the ide script's 53%.
    static let splitSide = LayoutSlot(id: "split.side", defaultFraction: 0.47, minFirst: 280, minSecond: 360)
    /// Landing: opener height vs. terminal (horizontal divider). The opener
    /// holds the centered summon card, so it takes the room (owner revision
    /// 2026-07-13: terminal is the bottom third).
    static let landingVertical = LayoutSlot(id: "landing.vertical", defaultFraction: 0.67, minFirst: 160, minSecond: 120)
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

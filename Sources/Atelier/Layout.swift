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

    /// Triptych only: the inner (editor/shell) split nested in this outer
    /// split, and the handle that sits where their dividers cross. Set by
    /// the session when it builds the tree; nil everywhere else.
    weak var innerSplit: LayoutSplitView?
    private var cornerHandle: SplitCornerHandle?

    /// Install the crossing-point handle. Needs `arrangesAllSubviews` off so
    /// the handle can be a plain subview floating over the arranged panes.
    func installCornerHandle(inner: LayoutSplitView) {
        innerSplit = inner
        let handle = SplitCornerHandle(outer: self, inner: inner)
        addSubview(handle, positioned: .above, relativeTo: nil)
        cornerHandle = handle
        needsLayout = true
    }

    /// NSSplitView claims a generous band around its divider before asking
    /// subviews, which swallowed the handle's centre — the exact spot you'd
    /// grab. The handle wins wherever it sits.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let handle = cornerHandle, !handle.isHidden,
           handle.frame.contains(convert(point, from: superview)) {
            return handle
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        guard let handle = cornerHandle, let inner = innerSplit,
              arrangedSubviews.count == 2, inner.arrangedSubviews.count == 2 else { return }
        let x = arrangedSubviews[0].frame.maxX + dividerThickness / 2
        let innerY = inner.arrangedSubviews[0].frame.maxY + inner.dividerThickness / 2
        let y = convert(NSPoint(x: 0, y: innerY), from: inner).y
        let size = SplitCornerHandle.size
        handle.frame = NSRect(x: x - size / 2, y: y - size / 2, width: size, height: size)
    }

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

/// The square where the triptych's two dividers cross. Invisible; the
/// cursor says what it does. Dragging it moves both dividers together —
/// the outer's x and the inner's y follow the pointer, each clamped to its
/// slot's minimums. PTY resizes freeze for the drag like any divider drag.
final class SplitCornerHandle: NSView {
    static let size: CGFloat = 18
    private unowned let outer: LayoutSplitView
    private unowned let inner: LayoutSplitView

    init(outer: LayoutSplitView, inner: LayoutSplitView) {
        self.outer = outer
        self.inner = inner
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        outer.onDividerDrag?(true)
        defer { outer.onDividerDrag?(false) }
        var current = event
        while current.type != .leftMouseUp {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            current = next
            if current.type == .leftMouseDragged { move(to: current.locationInWindow) }
        }
    }

    private func move(to windowPoint: NSPoint) {
        let px = outer.convert(windowPoint, from: nil).x
        let py = inner.convert(windowPoint, from: nil).y
        let outerMax = outer.bounds.width - outer.slot.minSecond
        let innerMax = inner.bounds.height - inner.slot.minSecond
        outer.setPosition(min(max(px, outer.slot.minFirst), outerMax), ofDividerAt: 0)
        inner.setPosition(min(max(py, inner.slot.minFirst), innerMax), ofDividerAt: 0)
    }
}

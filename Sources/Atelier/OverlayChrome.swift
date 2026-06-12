import AppKit

/// Shared physiology for the floating overlays (POLISH_PLAN §6) — the fan and
/// the palette, and later the M2 `⌘P` picker.

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

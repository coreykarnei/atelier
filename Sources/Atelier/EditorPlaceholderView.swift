import AppKit

/// The editor pane, as a placeholder through Milestone 1. The real VSCode-shaped
/// editor is Milestone 2 (TECHNICAL_PLAN §3.3); for now this just holds the slot in
/// the Triptych layout so the shell around it can be built and exercised.
///
/// It is a long-lived view: in Split mode it is removed from the split tree but not
/// destroyed, so toggling back to Triptych is lossless (MILESTONE_1 §3).
final class EditorPlaceholderView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.editorPlaceholderBackground.cgColor

        let label = NSTextField(labelWithString: "Editor · Milestone 2")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = Theme.chromeMutedText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // Keep the layer background correct if the view is reattached in a different
    // appearance context.
    override func updateLayer() {
        layer?.backgroundColor = Theme.editorPlaceholderBackground.cgColor
    }
}

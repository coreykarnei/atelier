import AppKit

/// The editor pane, as a placeholder through Milestone 1. The real VSCode-shaped
/// editor is Milestone 2 (TECHNICAL_PLAN §3.3); for now this just holds the slot in
/// the Triptych layout so the shell around it can be built and exercised.
///
/// It is a long-lived view: in Split mode it is removed from the split tree but not
/// destroyed, so toggling back to Triptych is lossless (MILESTONE_1 §3).
final class EditorPlaceholderView: NSView, WorkspacePane {
    /// Focus target for the focus manager — the placeholder itself, so `⌃⌘+hjkl` can
    /// land here even before the real editor exists.
    var focusView: NSView { self }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // A recessed well on the z-ramp: the editor doesn't exist yet, so its
        // slot reads as *below* the content plane.
        layer?.backgroundColor = Theme.Elevation.crust.cgColor

        let label = NSTextField(labelWithString: "Editor · Milestone 2")
        label.font = Theme.Typography.ui(Theme.Typography.body, weight: .medium)
        label.textColor = Theme.chromeMutedText
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // Keep the layer background correct if the view is reattached in a different
    // appearance context.
    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }
}

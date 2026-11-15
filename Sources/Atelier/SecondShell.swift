import AppKit

/// The second shell as the editor's slot shows it (2026-11-15, owner call:
/// "a clear way to get back to the editor"). A rail runs down its left
/// edge — the folded file tree's own width and material, so trading the
/// editor for the shell changes the tenant and nothing else — and at the
/// rail's foot, exactly where the tree's rail keeps the terminal button
/// that brought you here, sits the way back. One spot, both directions:
/// the pointer never has to travel to undo what it just did.
final class SecondShellHost: NSView, WorkspacePane {
    let pane = TerminalPane()
    var focusView: NSView { pane.focusView }

    /// The rail's button: back to the editor.
    var onBack: (() -> Void)?

    private let rail = NSView()
    private let edge = NSView()
    private let back = HoverPadButton(frame: .zero)

    /// Where a rail's foot button sits, shared with the file tree's rail so
    /// the two buttons land on the same pixels.
    static let footButtonSize: CGFloat = 20
    static let footButtonInset: CGFloat = 5

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        rail.wantsLayer = true
        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)
        edge.wantsLayer = true
        edge.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        edge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(edge)

        back.image = SlotGlyph.editor()
        back.contentTintColor = Theme.chromeText
        back.toolTip = "Back to the Editor (⌃`)"
        back.setAccessibilityLabel("Back to the editor")
        back.target = self
        back.action = #selector(backClicked)
        back.translatesAutoresizingMaskIntoConstraints = false
        rail.addSubview(back)

        addSubview(pane)
        let railWidth = FileExplorerView.railWidth
        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            // The rail's coat runs under its edge, as the tree's does: a
            // hairline is 6% white, and over bare blur it reads as a bright
            // line instead of a seam.
            rail.widthAnchor.constraint(equalToConstant: railWidth),
            edge.topAnchor.constraint(equalTo: topAnchor),
            edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: rail.trailingAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),
            back.centerXAnchor.constraint(equalTo: rail.centerXAnchor, constant: -0.5),
            back.bottomAnchor.constraint(equalTo: rail.bottomAnchor, constant: -Self.footButtonInset),
            back.widthAnchor.constraint(equalToConstant: Self.footButtonSize),
            back.heightAnchor.constraint(equalToConstant: Self.footButtonSize),
            pane.topAnchor.constraint(equalTo: topAnchor),
            pane.bottomAnchor.constraint(equalTo: bottomAnchor),
            pane.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            pane.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        applyWash()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged), name: Settings.didChange, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// The tree's own coat (crust, following the field-opacity slider).
    private func applyWash() {
        rail.layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    @objc private func appearanceChanged() { applyWash() }

    @objc private func backClicked() { onBack?() }
}

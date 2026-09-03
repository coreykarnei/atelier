import AppKit

/// The handful of owner-tunable preferences (there is deliberately no settings
/// UI "for every preference" — see CLAUDE.md non-goals). Two things earned a
/// control: the field opacity, and whether worktrees are part of the session
/// flow at all. Backed by UserDefaults; every change posts `didChange` and the
/// field surfaces re-read their tokens live.
enum Settings {
    static let didChange = Notification.Name("atelier.settings.didChange")

    private static let alphaKey = "field.alpha"
    private static let worktreesKey = "worktrees.enabled"

    /// Field opacity over the behind-window blur (Theme.fieldAlpha). 0.75 is
    /// the owner's Ghostty parity value. `ATELIER_FIELD_ALPHA` still wins for
    /// dev bisects.
    static var fieldAlpha: CGFloat {
        get {
            if let raw = ProcessInfo.processInfo.environment["ATELIER_FIELD_ALPHA"],
               let value = Double(raw), (0.0...1.0).contains(value) {
                return CGFloat(value)
            }
            let stored = UserDefaults.standard.double(forKey: alphaKey)
            return stored == 0 ? 0.75 : CGFloat(min(max(stored, 0.3), 1.0))
        }
        set {
            let clamped = min(max(newValue, 0.3), 1.0)
            guard clamped != fieldAlpha else { return }
            UserDefaults.standard.set(Double(clamped), forKey: alphaKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Off: `+` starts a session on the main checkout, no question asked.
    /// On: the worktree chooser appears first (MILESTONE_1 §6, revised).
    static var worktreesEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: worktreesKey) }
        set {
            guard newValue != worktreesEnabled else { return }
            UserDefaults.standard.set(newValue, forKey: worktreesKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
}

/// `⌘,` / the bar's gear: one small panel, two controls. Atelier speaks in
/// SF Pro here (§1.4); the panel is opaque chrome, not a field.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let alphaSlider = NSSlider()
    private let alphaValue = NSTextField(labelWithString: "")
    private let worktreesToggle = NSButton(checkboxWithTitle: "Enable worktrees", target: nil, action: nil)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.Elevation.surface0
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = Theme.Elevation.surface0.cgColor
        super.init(window: window)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let content = window?.contentView else { return }

        let alphaLabel = NSTextField(labelWithString: "Field opacity")
        alphaLabel.font = Theme.Typography.ui(Theme.Typography.body)
        alphaLabel.textColor = Theme.chromeText

        alphaSlider.minValue = 0.3
        alphaSlider.maxValue = 1.0
        alphaSlider.doubleValue = Double(Settings.fieldAlpha)
        alphaSlider.isContinuous = true
        alphaSlider.target = self
        alphaSlider.action = #selector(alphaChanged)

        alphaValue.font = Theme.Typography.mono(Theme.Typography.body)
        alphaValue.textColor = Theme.chromeMutedText
        alphaValue.alignment = .right
        refreshAlphaValue()

        let alphaHint = NSTextField(labelWithString: "How much the panes cover the blur behind the window. Text is never affected.")
        alphaHint.font = Theme.Typography.ui(Theme.Typography.small)
        alphaHint.textColor = Theme.chromeMutedText
        alphaHint.lineBreakMode = .byWordWrapping
        alphaHint.maximumNumberOfLines = 2

        worktreesToggle.attributedTitle = NSAttributedString(string: "Enable worktrees", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body),
            .foregroundColor: Theme.chromeText,
        ])
        worktreesToggle.state = Settings.worktreesEnabled ? .on : .off
        worktreesToggle.target = self
        worktreesToggle.action = #selector(worktreesChanged)

        let worktreesHint = NSTextField(labelWithString: "New sessions ask which worktree to start in, and can create one. Off: sessions start on the main checkout.")
        worktreesHint.font = Theme.Typography.ui(Theme.Typography.small)
        worktreesHint.textColor = Theme.chromeMutedText
        worktreesHint.lineBreakMode = .byWordWrapping
        worktreesHint.maximumNumberOfLines = 2

        let alphaRow = NSStackView(views: [alphaLabel, alphaSlider, alphaValue])
        alphaRow.orientation = .horizontal
        alphaRow.spacing = 10

        let stack = NSStackView(views: [alphaRow, alphaHint, worktreesToggle, worktreesHint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(18, after: alphaHint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18),
            alphaRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            alphaHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            worktreesHint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            alphaValue.widthAnchor.constraint(equalToConstant: 40),
        ])
    }

    func show() {
        alphaSlider.doubleValue = Double(Settings.fieldAlpha)
        worktreesToggle.state = Settings.worktreesEnabled ? .on : .off
        refreshAlphaValue()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refreshAlphaValue() {
        alphaValue.stringValue = String(format: "%.2f", Settings.fieldAlpha)
    }

    @objc private func alphaChanged() {
        Settings.fieldAlpha = CGFloat(alphaSlider.doubleValue)
        refreshAlphaValue()
    }

    @objc private func worktreesChanged() {
        Settings.worktreesEnabled = worktreesToggle.state == .on
    }
}

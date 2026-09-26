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
    private static let confirmCloseKey = "close.confirm"
    private static let autosaveKey = "editor.autosave"
    private static let soundsKey = "sessions.sounds"

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

    /// Ask before a tab's `×` closes a session (default on). The alert's
    /// "Don't ask again" flips this; Settings flips it back.
    static var confirmClose: Bool {
        get { UserDefaults.standard.object(forKey: confirmCloseKey) as? Bool ?? true }
        set {
            guard newValue != confirmClose else { return }
            UserDefaults.standard.set(newValue, forKey: confirmCloseKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// On: the editor writes the buffer a moment after every edit and never
    /// asks about unsaved changes. Off: `⌘S`, and the dirty guard.
    static var autosave: Bool {
        get { UserDefaults.standard.bool(forKey: autosaveKey) }
        set {
            guard newValue != autosave else { return }
            UserDefaults.standard.set(newValue, forKey: autosaveKey)
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Blow when a turn finishes, Tink when Claude needs you (default on).
    static var sounds: Bool {
        get { UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true }
        set {
            guard newValue != sounds else { return }
            UserDefaults.standard.set(newValue, forKey: soundsKey)
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

/// `⌘,` / the bar's gear: one compact panel, grouped by purpose. Atelier speaks in
/// SF Pro here (§1.4); the panel is opaque chrome, not a field.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let alphaSlider = NSSlider()
    private let alphaValue = NSTextField(labelWithString: "")
    private let worktreesToggle = NSButton(checkboxWithTitle: "Enable worktrees", target: nil, action: nil)
    private let confirmCloseToggle = NSButton(checkboxWithTitle: "Ask before closing a session", target: nil, action: nil)
    private let autosaveToggle = NSButton(checkboxWithTitle: "Autosave", target: nil, action: nil)
    private let soundsToggle = NSButton(checkboxWithTitle: "Sounds", target: nil, action: nil)
    private let soundsHint = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.Elevation.overlayFill
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = Theme.Elevation.overlayFill.cgColor
        super.init(window: window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsChanged), name: Settings.didChange, object: nil
        )
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build() {
        guard let content = window?.contentView else { return }

        let alphaLabel = NSTextField(labelWithString: "Pane opacity")
        alphaLabel.font = Theme.Typography.ui(Theme.Typography.body)
        alphaLabel.textColor = Theme.chromeText

        alphaSlider.minValue = 0.3
        alphaSlider.maxValue = 1.0
        alphaSlider.doubleValue = Double(Settings.fieldAlpha)
        alphaSlider.isContinuous = true
        alphaSlider.setAccessibilityLabel("Pane opacity")
        alphaSlider.target = self
        alphaSlider.action = #selector(alphaChanged)

        alphaValue.font = Theme.Typography.mono(Theme.Typography.body)
        alphaValue.textColor = Theme.chromeMutedText
        alphaValue.alignment = .right
        refreshAlphaValue()

        let alphaHint = NSTextField(labelWithString: "Adjust the background; text stays fully legible.")
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

        let worktreesHint = NSTextField(labelWithString: "Choose or create a worktree when starting a session.")
        worktreesHint.font = Theme.Typography.ui(Theme.Typography.small)
        worktreesHint.textColor = Theme.chromeMutedText
        worktreesHint.lineBreakMode = .byWordWrapping
        worktreesHint.maximumNumberOfLines = 2

        confirmCloseToggle.attributedTitle = NSAttributedString(string: "Ask before closing a session", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body),
            .foregroundColor: Theme.chromeText,
        ])
        confirmCloseToggle.state = Settings.confirmClose ? .on : .off
        confirmCloseToggle.target = self
        confirmCloseToggle.action = #selector(confirmCloseChanged)

        let confirmHint = NSTextField(labelWithString: "Confirm before closing from a session’s close button.")
        confirmHint.font = Theme.Typography.ui(Theme.Typography.small)
        confirmHint.textColor = Theme.chromeMutedText
        confirmHint.lineBreakMode = .byWordWrapping
        confirmHint.maximumNumberOfLines = 2

        autosaveToggle.attributedTitle = NSAttributedString(string: "Autosave", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body),
            .foregroundColor: Theme.chromeText,
        ])
        autosaveToggle.state = Settings.autosave ? .on : .off
        autosaveToggle.target = self
        autosaveToggle.action = #selector(autosaveChanged)

        let autosaveHint = NSTextField(labelWithString: "Save after each edit. When off, use ⌘S to save.")
        autosaveHint.font = Theme.Typography.ui(Theme.Typography.small)
        autosaveHint.textColor = Theme.chromeMutedText
        autosaveHint.lineBreakMode = .byWordWrapping
        autosaveHint.maximumNumberOfLines = 2

        soundsToggle.attributedTitle = NSAttributedString(string: "Sounds", attributes: [
            .font: Theme.Typography.ui(Theme.Typography.body),
            .foregroundColor: Theme.chromeText,
        ])
        soundsToggle.target = self
        soundsToggle.action = #selector(soundsChanged)
        soundsHint.font = Theme.Typography.ui(Theme.Typography.small)
        soundsHint.lineBreakMode = .byWordWrapping
        soundsHint.maximumNumberOfLines = 3
        refreshSounds()

        func heading(_ title: String) -> NSTextField {
            let label = NSTextField(labelWithString: title)
            label.font = Theme.Typography.ui(Theme.Typography.small, weight: .semibold)
            label.textColor = Theme.chromeText
            return label
        }
        func separator() -> NSBox {
            let line = NSBox(); line.boxType = .custom; line.borderWidth = 0
            line.fillColor = Theme.Elevation.frameLine
            line.heightAnchor.constraint(equalToConstant: 1).isActive = true
            return line
        }
        let alphaRow = NSStackView(views: [alphaLabel, NSView(), alphaValue])
        alphaRow.orientation = .horizontal
        alphaRow.spacing = 10
        let rule1 = separator(), rule2 = separator()
        let appearance = heading("Appearance"), editing = heading("Editing"), sessions = heading("Sessions")
        let views: [NSView] = [appearance, alphaRow, alphaSlider, alphaHint, rule1,
            editing, autosaveToggle, autosaveHint, rule2,
            sessions, worktreesToggle, worktreesHint, confirmCloseToggle, confirmHint, soundsToggle, soundsHint]
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: appearance)
        stack.setCustomSpacing(12, after: editing)
        stack.setCustomSpacing(12, after: sessions)
        stack.setCustomSpacing(16, after: alphaHint)
        stack.setCustomSpacing(16, after: autosaveHint)
        stack.setCustomSpacing(12, after: rule1)
        stack.setCustomSpacing(12, after: rule2)
        stack.setCustomSpacing(12, after: worktreesHint)
        stack.setCustomSpacing(12, after: confirmHint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        for view in [alphaRow, alphaSlider, alphaHint, autosaveHint, worktreesHint, confirmHint, soundsHint, rule1, rule2] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for hint in [alphaHint, autosaveHint, worktreesHint, confirmHint, soundsHint] {
            hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            alphaValue.widthAnchor.constraint(equalToConstant: 42),
        ])
    }

    func show() {
        autosaveToggle.state = Settings.autosave ? .on : .off
        alphaSlider.doubleValue = Double(Settings.fieldAlpha)
        worktreesToggle.state = Settings.worktreesEnabled ? .on : .off
        confirmCloseToggle.state = Settings.confirmClose ? .on : .off
        refreshAlphaValue()
        refreshSounds()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func refreshAlphaValue() {
        alphaValue.stringValue = String(format: "%.0f%%", Settings.fieldAlpha * 100)
    }

    @objc private func alphaChanged() {
        Settings.fieldAlpha = CGFloat(alphaSlider.doubleValue)
        refreshAlphaValue()
    }

    @objc private func confirmCloseChanged() {
        Settings.confirmClose = confirmCloseToggle.state == .on
    }

    @objc private func worktreesChanged() {
        Settings.worktreesEnabled = worktreesToggle.state == .on
    }

    @objc private func soundsChanged() {
        Settings.sounds = soundsToggle.state == .on
    }

    /// The toggle, and a hint that says when Claude's own settings already
    /// make the sound — Atelier stays quiet then rather than ring twice.
    private func refreshSounds() {
        soundsToggle.state = Settings.sounds ? .on : .off
        let theirs = !AgentHooks.userSoundHooks().isEmpty
        soundsHint.stringValue = theirs
            ? "Your Claude settings already play a sound when a turn ends, so Atelier doesn't add its own. To hear Atelier's, have that hook skip when ATELIER_TAB is set. Off silences terminal bells."
            : "Blow when a turn finishes, Tink when Claude needs you. Off also silences terminal bells."
        soundsHint.textColor = theirs ? Theme.accentPeach : Theme.chromeMutedText
    }

    @objc private func autosaveChanged() {
        Settings.autosave = autosaveToggle.state == .on
    }

    /// The File menu's Autosave item flips the same switch; keep the box honest.
    @objc private func settingsChanged() {
        alphaSlider.doubleValue = Double(Settings.fieldAlpha)
        refreshAlphaValue()
        autosaveToggle.state = Settings.autosave ? .on : .off
        worktreesToggle.state = Settings.worktreesEnabled ? .on : .off
        confirmCloseToggle.state = Settings.confirmClose ? .on : .off
        refreshSounds()
    }
}

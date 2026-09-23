import AppKit

/// What a project can ask of the window it lives in.
protocol ProjectHost: AnyObject {
    /// Bring this project on screen and the window forward.
    func activate(_ project: ProjectController)
    func projectDidChangeTitle(_ project: ProjectController)
    /// Sessions were added/removed/re-badged: the project tab's marks follow.
    func projectDidChangeSessions(_ project: ProjectController)
}

/// The mantle wash under the titlebar strip (§3.1). Mirrors the field
/// surfaces' translucency handling.
private final class TitlebarWashView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilityDisplayChanged),
            name: Settings.didChange,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    /// The hidden-title titlebar passes clicks through to this wash, so the
    /// system's double-click-titlebar action has to be re-spoken here:
    /// zoom (the default), or minimize when the user has set it so.
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount == 2, let window else {
            super.mouseDown(with: event)
            return
        }
        let action = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleActionOnDoubleClick"] as? String
        switch action {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}

/// The app's window class: reports first-responder changes so the focus
/// articulation (hairline + caret truth) can track clicks as well as chords.
final class AtelierWindow: NSWindow {
    var onFirstResponderChange: (() -> Void)?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted { onFirstResponderChange?() }
        return accepted
    }
}

/// The one window (VISION: single-window). Projects are its tabs, drawn by
/// Atelier in the titlebar row beside the traffic lights (`ProjectStripView`,
/// 2026-09-10 — replacing native window tabbing, whose bar couldn't be
/// tinted, rounded, or made to carry the sessions' attention marks). Each
/// project's content is a `ProjectController.view` filling the area below
/// the strip; one is visible, the rest keep running hidden.
final class WorkspaceWindowController: NSWindowController, NSWindowDelegate, ProjectHost {
    private(set) var projects: [ProjectController] = []
    private(set) var activeIndex = 0
    var activeProject: ProjectController? {
        projects.indices.contains(activeIndex) ? projects[activeIndex] : nil
    }

    private let projectArea = NSView()
    private let strip = ProjectStripView()
    private var stripHeight: NSLayoutConstraint?

    init() {
        let window = AtelierWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "New Tab"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        // §2.9: transparent, native blur — the aesthetic is a spec
        // requirement. The titlebar region still reads mantle via
        // TitlebarWashView, translucent over the blur like every field
        // surface.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        // Projects are Atelier's own tabs; AppKit must not offer to tab the
        // window itself (or inject its tab items into the Window menu).
        window.tabbingMode = .disallowed

        // The blur is the WindowServer's, not a material (see
        // WindowBlur.swift): NSVisualEffectView materials carry their own
        // near-opaque tint, and two attempts at "more translucent" materials
        // still compounded to a window the owner read as fully opaque. The
        // content view is a bare clear container; the fields' fieldAlpha
        // wash over the blurred desktop is the whole look — Ghostty's
        // pipeline, which is the target feel.
        let container = NSView()
        container.wantsLayer = true
        window.contentView = container
        window.appearance = NSAppearance(named: .darkAqua)

        super.init(window: window)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("AtelierMainWindow")
        if !WindowBackgroundBlur.apply(to: window, radius: Theme.backgroundBlurRadius) {
            // No CGS symbols (future-macOS insurance): fall back to the
            // material blur rather than a raw see-through window.
            NSLog("Atelier: CGS window blur unavailable; falling back to NSVisualEffectView")
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(blur, positioned: .below, relativeTo: nil)
            NSLayoutConstraint.activate([
                blur.topAnchor.constraint(equalTo: container.topAnchor),
                blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        buildChrome(in: container, window: window)
        observeFocus(of: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildChrome(in container: NSView, window: NSWindow) {
        // With .fullSizeContentView the content view extends under the
        // titlebar; the project area pins below the content layout guide so
        // panes never draw through the strip.
        let contentTop = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? container.topAnchor

        // §3.1: the titlebar region gets the same mantle-over-blur wash as
        // the bottom bar — one material language from the top edge down.
        let wash = TitlebarWashView()
        wash.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(wash)

        // The strip is its own row under the traffic-light row: tabs divide
        // the full width, as native window tabs did. It collapses to nothing
        // with a single project (nothing to switch between).
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.onSelect = { [weak self] id in
            guard let self, let index = self.projects.firstIndex(where: { ObjectIdentifier($0) == id }) else { return }
            self.activate(index: index)
        }
        strip.onClose = { [weak self] id in
            guard let self, let project = self.projects.first(where: { ObjectIdentifier($0) == id }) else { return }
            self.close(project)
        }
        strip.onNew = { (NSApp.delegate as? AppDelegate)?.newProject(nil) }
        container.addSubview(strip)

        projectArea.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(projectArea)

        let stripHeight = strip.heightAnchor.constraint(equalToConstant: 0)
        self.stripHeight = stripHeight
        NSLayoutConstraint.activate([
            wash.topAnchor.constraint(equalTo: container.topAnchor),
            wash.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            wash.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            wash.bottomAnchor.constraint(equalTo: strip.bottomAnchor),

            strip.topAnchor.constraint(equalTo: contentTop),
            strip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stripHeight,

            projectArea.topAnchor.constraint(equalTo: strip.bottomAnchor),
            projectArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            projectArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            projectArea.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    // MARK: Focus articulation (POLISH_PLAN Phase 1)

    private func observeFocus(of window: NSWindow) {
        // Every focus change funnels through makeFirstResponder — ours and
        // AppKit's (clicks) — so the subclass hook is the one reliable signal.
        (window as? AtelierWindow)?.onFirstResponderChange = { [weak self] in
            self?.activeProject?.refreshFocusArticulation()
        }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowKeyDidChange),
                           name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(windowKeyDidChange),
                           name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc private func windowKeyDidChange() {
        activeProject?.refreshFocusArticulation()
    }

    // MARK: Projects

    /// Adopt a project as a new tab (at the end). `activate` brings it on
    /// screen; otherwise it starts hidden (restore fills the strip first,
    /// then picks the tab that was active at quit).
    func add(_ project: ProjectController, activate: Bool) {
        project.host = self
        project.isActive = false
        project.view.isHidden = true
        projectArea.addSubview(project.view)
        NSLayoutConstraint.activate([
            project.view.topAnchor.constraint(equalTo: projectArea.topAnchor),
            project.view.bottomAnchor.constraint(equalTo: projectArea.bottomAnchor),
            project.view.leadingAnchor.constraint(equalTo: projectArea.leadingAnchor),
            project.view.trailingAnchor.constraint(equalTo: projectArea.trailingAnchor),
        ])
        projects.append(project)
        if activate || projects.count == 1 {
            self.activate(index: projects.count - 1)
        } else {
            refreshStrip()
        }
    }

    func activate(index: Int) {
        guard projects.indices.contains(index) else { return }
        let incoming = projects[index]
        if let outgoing = activeProject, outgoing !== incoming {
            outgoing.isActive = false
            outgoing.view.isHidden = true
        }
        activeIndex = index
        incoming.isActive = true
        incoming.view.isHidden = false
        window?.title = incoming.title
        window?.makeFirstResponder(incoming.preferredFocusView)
        incoming.didBecomeVisible()
        incoming.refreshFocusArticulation()
        refreshStrip()
    }

    func activateNext() {
        guard !projects.isEmpty else { return }
        activate(index: (activeIndex + 1) % projects.count)
    }

    func activatePrevious() {
        guard !projects.isEmpty else { return }
        activate(index: (activeIndex - 1 + projects.count) % projects.count)
    }

    /// The close button is Quit (2026-09-23, owner report: a relaunch lost
    /// every session). It used to tear the projects down first and quit
    /// with nothing left to snapshot — no gesture for "I'm done with
    /// these": in a single-window app the red button is how you leave, and
    /// leaving keeps your place, the same as ⌘Q. Ending sessions stays a
    /// per-tab act (⌘W, Close Project); the last project closing still
    /// closes the window directly (`close()` never asks this).
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(sender)
        return false // reached only if the quit was cancelled
    }

    /// Close a project: its sessions die (remote ones included — this is a
    /// deliberate "I'm done with this project"). Unsaved buffers get the
    /// informative refusal first (§5), naming the files. The last project
    /// closing closes the window, and with it the app.
    func close(_ project: ProjectController) {
        let dirty = project.dirtyBufferPaths
        guard !dirty.isEmpty, let window else {
            remove(project)
            return
        }
        let alert = NSAlert()
        alert.messageText = dirty.count == 1
            ? "\((dirty[0] as NSString).lastPathComponent) has unsaved changes"
            : "\(dirty.count) files have unsaved changes"
        alert.informativeText = "Closing \(project.title) will discard them."
        let label = NSTextField(labelWithString: dirty.map { ($0 as NSString).lastPathComponent }.joined(separator: "\n"))
        label.font = Theme.Typography.mono(Theme.Typography.small)
        label.textColor = Theme.chromeText
        label.frame = NSRect(x: 0, y: 0, width: 320, height: label.fittingSize.height)
        alert.accessoryView = label
        alert.addButton(withTitle: "Save All and Close")
        alert.addButton(withTitle: "Discard and Close")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                do {
                    try project.saveAllDirtyBuffers()
                    self?.remove(project)
                } catch {
                    let failure = NSAlert()
                    failure.alertStyle = .warning
                    failure.messageText = "Couldn't save"
                    failure.informativeText = error.localizedDescription
                    failure.beginSheetModal(for: window)
                }
            case .alertSecondButtonReturn:
                self?.remove(project)
            default:
                break
            }
        }
    }

    private func remove(_ project: ProjectController) {
        guard let index = projects.firstIndex(where: { $0 === project }) else { return }
        project.terminateAllSessions()
        project.isActive = false
        project.view.removeFromSuperview()
        project.host = nil
        projects.remove(at: index)
        if projects.isEmpty {
            window?.close()
            return
        }
        if index == activeIndex {
            activate(index: min(index, projects.count - 1))
        } else {
            if index < activeIndex { activeIndex -= 1 }
            refreshStrip()
        }
    }

    // MARK: ProjectHost

    func activate(_ project: ProjectController) {
        if let index = projects.firstIndex(where: { $0 === project }) {
            activate(index: index)
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func projectDidChangeTitle(_ project: ProjectController) {
        if project === activeProject { window?.title = project.title }
        refreshStrip()
    }

    func projectDidChangeSessions(_ project: ProjectController) {
        refreshStrip()
    }

    private func refreshStrip() {
        let visible = projects.count > 1
        stripHeight?.constant = visible ? ProjectStripView.rowHeight : 0
        strip.isHidden = !visible
        strip.update(tabs: projects.enumerated().map { index, project in
            ProjectTabInfo(
                id: ObjectIdentifier(project),
                title: project.title,
                isActive: index == activeIndex,
                marks: project.attentionMarks
            )
        })
    }
}

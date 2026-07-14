import AppKit
import Darwin

/// Recently opened project roots, most-recent-first, persisted in UserDefaults.
/// Recorded on session promote (LandingView → IDE).
enum RecentsStore {
    private static let key = "landing.recents"

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ path: String) {
        var list = all().filter { $0 != path }
        list.insert(path, at: 0)
        UserDefaults.standard.set(Array(list.prefix(12)), forKey: key)
    }

    /// Drop entries whose directories no longer exist — a recent that can't be
    /// opened is a promise the list shouldn't keep making. Remote (`ssh://`)
    /// entries have no local directory to check; their host's continued
    /// existence in ~/.ssh/config is checked at offer time instead.
    static func prune() {
        let list = all()
        let existing = list.filter {
            $0.hasPrefix("ssh://") || FileManager.default.fileExists(atPath: $0)
        }
        if existing.count != list.count {
            UserDefaults.standard.set(existing, forKey: key)
        }
    }
}

struct LandingEntry {
    let name: String
    /// A local directory, or an `ssh://host:dir` remote target id.
    let path: String
    let isRecent: Bool
    /// Set for remote entries: the ssh host they open on.
    var host: String? = nil
}

/// The landing pane (MILESTONE_1 §2.1). Rebuilt on the summon idiom
/// (interaction pass, 2026-07-13): `⌘T` puts the cursor in a filter field over
/// recents + repos — the first keystroke lands, `↩` opens the top match, a
/// single click opens a row, and the offer refreshes every time the landing is
/// shown so it never lists a repo that's gone or misses one that's new.
///
/// The summon lives on a centered raised card in the upper-middle of the pane
/// (owner direction 2026-07-13) — the Raycast posture: the card hugs its
/// results, the chord hints sit quietly beneath it, and the terminal keeps the
/// bottom third. The card fills `base` so the surface0 highlight reads against
/// it, per the elevation ramp.
final class LandingView: NSView, WorkspacePane {
    /// Called with the chosen project root.
    var onOpen: ((String) -> Void)?

    /// Called with the chosen remote target (host, remote dir).
    var onOpenRemote: ((String, String) -> Void)?

    var focusView: NSView { summon.focusField }

    private let summon: SummonList
    private let cardHost = NSView()
    private let card = NSView()
    private var listHeight: NSLayoutConstraint?
    private let defaultFolder: String
    private var entries: [LandingEntry] = []
    private var emptyHint: NSTextField?
    private let hintLabel = NSTextField(labelWithString: "")

    /// The card never grows past this many points of list — exactly 12 rows,
    /// so the cap never cuts a row mid-height at the card's edge.
    private static let maxListHeight: CGFloat = 12 * 24

    init(defaultFolder: String) {
        self.defaultFolder = defaultFolder
        self.summon = SummonList(style: .init(
            placeholder: "Open a project…",
            // The query is a repo name — terminal-pasteable, so mono (§1.4);
            // the placeholder is Atelier speaking, so it stays ui.
            fieldFont: Theme.Typography.mono(Theme.Typography.body),
            placeholderFont: Theme.Typography.ui(Theme.Typography.body),
            rowHeight: 24,
            // Rows align with the field's text axis above them.
            rowInset: 14,
            noMatchText: "No matching projects",
            escClearsQueryFirst: true
        ))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor

        cardHost.wantsLayer = true
        cardHost.shadow = Theme.Elevation.raisedShadow
        cardHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardHost)

        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.Elevation.base.cgColor
        card.layer?.cornerRadius = Theme.Elevation.radiusLarge
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        cardHost.addSubview(card)

        // Light from above: the raised card's 1 px top hairline.
        let topHairline = NSBox()
        topHairline.boxType = .custom
        topHairline.fillColor = Theme.Elevation.hairline
        topHairline.borderWidth = 0
        topHairline.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(topHairline)

        summon.translatesAutoresizingMaskIntoConstraints = false
        summon.onActivate = { [weak self] item in self?.open(path: item.id) }
        summon.onContentChange = { [weak self] in self?.trackContentHeight() }
        summon.onQueryChange = { [weak self] query in self?.injectRemoteQueryItem(for: query) }
        card.addSubview(summon)

        // Two-voice hint (§1.4): chords and the `ide` command are mono, the
        // prose around them is Atelier speaking.
        let hint = NSMutableAttributedString()
        func prose(_ s: String) { hint.append(NSAttributedString(string: s, attributes: [
            .font: Theme.Typography.ui(Theme.Typography.small),
            .foregroundColor: Theme.chromeMutedText,
        ])) }
        func chord(_ s: String) { hint.append(NSAttributedString(string: s, attributes: [
            .font: Theme.Typography.mono(Theme.Typography.small),
            .foregroundColor: Theme.chromeText,
        ])) }
        chord("↩"); prose(" open · "); chord("⌘↩"); prose(" "); chord("ide")
        prose(" in terminal dir · "); chord("⌃⌘j"); prose(" shell")
        hintLabel.attributedStringValue = hint
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        // The field sits at ~26% of the pane height — the Spotlight posture:
        // the field holds still while the list grows downward beneath it.
        let topSpace = NSLayoutGuide()
        addLayoutGuide(topSpace)

        let bottomGuard = cardHost.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)
        NSLayoutConstraint.activate([
            topSpace.topAnchor.constraint(equalTo: topAnchor),
            topSpace.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.26),

            cardHost.topAnchor.constraint(equalTo: topSpace.bottomAnchor),
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardHost.widthAnchor.constraint(equalToConstant: 560),
            bottomGuard,

            card.topAnchor.constraint(equalTo: cardHost.topAnchor),
            card.leadingAnchor.constraint(equalTo: cardHost.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: cardHost.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: cardHost.bottomAnchor),

            topHairline.topAnchor.constraint(equalTo: card.topAnchor),
            topHairline.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            topHairline.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            topHairline.heightAnchor.constraint(equalToConstant: 1),

            summon.topAnchor.constraint(equalTo: card.topAnchor),
            summon.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            summon.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            summon.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            hintLabel.topAnchor.constraint(equalTo: cardHost.bottomAnchor, constant: 10),
            hintLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        // When the pane runs short, the list compresses before the card can
        // cross the divider.
        let height = summon.makeListHeightConstraint(constant: 0)
        height.priority = NSLayoutConstraint.Priority(999)
        height.isActive = true
        listHeight = height

        refresh()
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
        NotificationCenter.default.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        card.layer?.backgroundColor = Theme.Elevation.base.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        card.layer?.backgroundColor = Theme.Elevation.base.cgColor
    }

    /// The card hugs its results (the palette's §6 height-tracking, embedded):
    /// grows as matches appear, shrinks as the query narrows, one-line floor
    /// for the no-match state.
    private func trackContentHeight() {
        guard let listHeight else { return }
        let newHeight = min(summon.contentHeight, Self.maxListHeight)
        guard listHeight.constant != newHeight else { return }
        if window == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            listHeight.constant = newHeight
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                listHeight.animator().constant = newHeight
                self.layoutSubtreeIfNeeded()
            }
        }
    }

    /// Stale offers are lies: re-scan whenever the landing (re)joins a window
    /// or its window comes back to key — a repo cloned in another app appears,
    /// a recent promoted elsewhere reorders, a deleted directory drops out.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        refresh()
    }

    @objc private func windowBecameKey() { refresh() }

    /// Re-scan recents + repos + ssh hosts and re-offer them; the live query
    /// survives.
    func refresh() {
        RecentsStore.prune()
        knownHosts = SSHConfigHosts.all()
        entries = Self.entries(defaultFolder: defaultFolder, hosts: knownHosts)
        // Through the injector, not setItems directly: a live `host:dir`
        // query must survive a background refresh (window became key).
        injectRemoteQueryItem(for: summon.query)
        updateEmptyHint()
    }

    private static func items(for entries: [LandingEntry]) -> [SummonItem] {
        entries.map { entry in
            SummonItem(
                id: entry.path,
                text: rowText(for: entry),
                matchText: entry.host == nil
                    ? entry.name.lowercased()
                    : entry.path.dropFirst("ssh://".count).lowercased(),
                chord: nil
            )
        }
    }

    private func open(path: String) {
        if let target = RemoteTarget.parse(path) {
            onOpenRemote?(target.host, target.dir)
            return
        }
        // The offer can rot between the scan and the click; re-check the truth
        // at decision time and quietly re-scan instead of opening a dead root.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            refresh()
            return
        }
        onOpen?(path)
    }

    /// Recents (that still exist) first, then git repos in the default folder,
    /// then ssh hosts (§remote): every place you can start is one list.
    static func entries(defaultFolder: String, hosts: [String] = []) -> [LandingEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [LandingEntry] = []

        for path in RecentsStore.all() {
            guard seen.insert(path).inserted else { continue }
            if let target = RemoteTarget.parse(path) {
                // A recent on a host that left ssh config can't be opened.
                guard hosts.contains(target.host) else { continue }
                out.append(LandingEntry(
                    name: target.host, path: path, isRecent: true, host: target.host
                ))
            } else if fm.fileExists(atPath: path) {
                out.append(LandingEntry(name: (path as NSString).lastPathComponent, path: path, isRecent: true))
            }
        }

        if let children = try? fm.contentsOfDirectory(atPath: defaultFolder) {
            for child in children.sorted(by: { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
                let full = "\(defaultFolder)/\(child)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue,
                      fm.fileExists(atPath: "\(full)/.git"),
                      seen.insert(full).inserted else { continue }
                out.append(LandingEntry(name: child, path: full, isRecent: false))
            }
        }

        for host in hosts {
            let target = RemoteTarget(host: host, dir: "~")
            guard seen.insert(target.id).inserted else { continue }
            out.append(LandingEntry(name: host, path: target.id, isRecent: false, host: host))
        }
        return out
    }

    private static func rowText(for entry: LandingEntry) -> NSAttributedString {
        let detail: String
        if entry.host != nil {
            let dir = RemoteTarget.parse(entry.path)?.dir ?? "~"
            detail = dir == "~" ? "ssh" : "ssh · \(dir)"
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            detail = (entry.path as NSString).deletingLastPathComponent
                .replacingOccurrences(of: home, with: "~")
        }

        let text = NSMutableAttributedString()
        if entry.isRecent {
            text.append(NSAttributedString(string: "● ", attributes: [
                .font: NSFont.systemFont(ofSize: 7),
                .foregroundColor: Theme.accentGreen,
                .baselineOffset: 2,
            ]))
        }
        // Repo names and paths are things you could paste into a terminal: mono.
        text.append(NSAttributedString(string: entry.name, attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeText,
        ]))
        text.append(NSAttributedString(string: "  \(detail)", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.small),
            .foregroundColor: Theme.chromeMutedText,
        ]))
        return text
    }

    // MARK: Remote targets (§remote)

    private var knownHosts: [String] = []

    /// `host:dir` typed into the filter injects a synthetic top row aimed at
    /// that directory on that host — the colon defeats subsequence matching
    /// against the bare host row, so the row is *made*, not matched.
    private func injectRemoteQueryItem(for query: String) {
        var items = Self.items(for: entries)
        if let target = parseRemoteQuery(query) {
            let text = NSMutableAttributedString()
            text.append(NSAttributedString(string: "\(target.host):\(target.dir)", attributes: [
                .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
                .foregroundColor: Theme.chromeText,
            ]))
            text.append(NSAttributedString(string: "  open on \(target.host)", attributes: [
                .font: Theme.Typography.ui(Theme.Typography.small),
                .foregroundColor: Theme.chromeMutedText,
            ]))
            items.insert(SummonItem(
                id: target.id,
                text: text,
                matchText: query.lowercased().trimmingCharacters(in: .whitespaces),
                chord: nil
            ), at: 0)
        }
        summon.setItems(items)
    }

    private func parseRemoteQuery(_ query: String) -> RemoteTarget? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard let colon = q.firstIndex(of: ":") else { return nil }
        let host = String(q[..<colon])
        let rest = String(q[q.index(after: colon)...])
        guard !rest.isEmpty, knownHosts.contains(host) else { return nil }
        let dir = rest.hasPrefix("/") || rest.hasPrefix("~") ? rest : "~/\(rest)"
        return RemoteTarget(host: host, dir: dir)
    }

    /// First-launch empty state (§5): one designed two-voice line, not a blank
    /// list. Atelier speaks SF Pro; `cd` and the chord are mono.
    private func updateEmptyHint() {
        if entries.isEmpty {
            guard emptyHint == nil else { return }
            let line = NSMutableAttributedString()
            func ui(_ s: String) { line.append(NSAttributedString(string: s, attributes: [
                .font: Theme.Typography.ui(Theme.Typography.body),
                .foregroundColor: Theme.chromeMutedText,
            ])) }
            func mono(_ s: String) { line.append(NSAttributedString(string: s, attributes: [
                .font: Theme.Typography.mono(Theme.Typography.body),
                .foregroundColor: Theme.chromeText,
            ])) }
            ui("Nothing yet — ")
            mono("cd")
            ui(" into a repo and ")
            mono("⌘↩")
            let hint = NSTextField(labelWithAttributedString: line)
            hint.translatesAutoresizingMaskIntoConstraints = false
            addSubview(hint)
            NSLayoutConstraint.activate([
                hint.centerXAnchor.constraint(equalTo: centerXAnchor),
                hint.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 18),
            ])
            emptyHint = hint
        } else if let hint = emptyHint {
            hint.removeFromSuperview()
            emptyHint = nil
        }
    }
}

/// Working directory of a live process (the shell's cwd for "open IDE here"),
/// via libproc — same data `lsof -d cwd` reports.
enum ProcessCwd {
    static func cwd(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            guard let base = raw.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }
}

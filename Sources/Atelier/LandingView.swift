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
    /// Sessions waiting on the shelf here (`ProjectShelf`), one mark each:
    /// opening this row brings them back rather than starting one fresh.
    var shelved: [Session.Attention] = []
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

    /// The landing terminal's live working directory — the same truth `⌘↩`
    /// promotes on. Path-mode queries resolve relative to it first: the
    /// summon is an extension of that terminal, so `/foo` means what it
    /// would mean rendered there. Nil (or unset) falls back to home.
    var liveCwd: (() -> String?)?

    var focusView: NSView { summon.focusField }

    private let summon: SummonList
    private let cardHost = NSView()
    private let card = NSView()
    private var listHeight: NSLayoutConstraint?
    private var cardWidth: NSLayoutConstraint?
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
        card.layer?.borderWidth = 1
        card.layer?.borderColor = Theme.Elevation.hairline.cgColor
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
        let hintParagraph = NSMutableParagraphStyle()
        hintParagraph.alignment = .center
        hintParagraph.lineBreakMode = .byWordWrapping
        hint.addAttribute(.paragraphStyle, value: hintParagraph, range: NSRange(location: 0, length: hint.length))
        hintLabel.attributedStringValue = hint
        hintLabel.alignment = .center
        hintLabel.lineBreakMode = .byWordWrapping
        hintLabel.maximumNumberOfLines = 2
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        // The field sits at ~26% of the pane height — the Spotlight posture:
        // the field holds still while the list grows downward beneath it.
        let topSpace = NSLayoutGuide()
        addLayoutGuide(topSpace)

        let width = cardHost.widthAnchor.constraint(equalToConstant: 560)
        cardWidth = width
        let bottomGuard = cardHost.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -16)
        NSLayoutConstraint.activate([
            topSpace.topAnchor.constraint(equalTo: topAnchor),
            topSpace.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.26),

            cardHost.topAnchor.constraint(equalTo: topSpace.bottomAnchor),
            cardHost.centerXAnchor.constraint(equalTo: centerXAnchor),
            width,
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
            hintLabel.widthAnchor.constraint(equalTo: cardHost.widthAnchor),
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
        NotificationCenter.default.removeObserver(self)
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        card.layer?.backgroundColor = Theme.Elevation.base.cgColor
    }

    /// Dead space is a return path: a click anywhere off the card (the terminal
    /// stole focus, the eye wanders back up) puts the cursor straight back in
    /// the field — no aiming at the field itself required. Card and list
    /// clicks hit their own subviews and never reach here.
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(summon.focusField)
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        card.layer?.backgroundColor = Theme.Elevation.base.cgColor
    }

    /// The card hugs its results (the palette's §6 height-tracking, embedded):
    /// grows as matches appear, shrinks as the query narrows, one-line floor
    /// for the no-match state.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        cardWidth?.constant = min(560, max(0, newSize.width - 40))
        listHeight?.constant = min(summon.contentHeight, availableListHeight)
    }

    private var availableListHeight: CGFloat {
        bounds.height > 0 ? max(24, min(Self.maxListHeight, bounds.height * 0.74 - 100)) : Self.maxListHeight
    }

    private func trackContentHeight() {
        guard let listHeight else { return }
        let newHeight = min(summon.contentHeight, availableListHeight)
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
            // ⇥ on a repo fills its name; on a bare host, `host:` — priming
            // the host:dir syntax; on a remote recent, its full host:dir.
            let fill: String
            if entry.host == nil {
                fill = entry.name
            } else if let target = RemoteTarget.parse(entry.path) {
                fill = target.dir == "~" ? "\(target.host):" : "\(target.host):\(target.dir)"
            } else {
                fill = entry.name
            }
            return SummonItem(
                id: entry.path,
                text: rowText(for: entry),
                matchText: entry.host == nil
                    ? entry.name.lowercased()
                    : entry.path.dropFirst("ssh://".count).lowercased(),
                chord: nil,
                fill: fill
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

    /// Shelved projects, then recents (that still exist), then git repos in the default folder,
    /// then ssh hosts (§remote): every place you can start is one list.
    static func entries(defaultFolder: String, hosts: [String] = []) -> [LandingEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [LandingEntry] = []

        // Shelved projects lead: something is waiting there, whether or not
        // the place was ever a recent (a CLI open never records one).
        let shelf = ProjectShelf.marks()
        for path in shelf.map(\.key) + RecentsStore.all() {
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

        if !shelf.isEmpty {
            let marks = Dictionary(shelf.map { ($0.key, $0.marks) }, uniquingKeysWith: { a, _ in a })
            for i in out.indices { out[i].shelved = marks[out[i].path] ?? [] }
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
        // Repo names and paths are things you could paste into a terminal: mono.
        text.append(NSAttributedString(string: entry.name, attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeText,
        ]))
        if !entry.shelved.isEmpty {
            // The sessions opening this row brings back, one dot each in the
            // state it returns in — the project tab's marks, before the tab
            // exists. A session that never ran a turn has no state: a dim dot.
            text.append(NSAttributedString(string: " ", attributes: [
                .font: Theme.Typography.mono(Theme.Typography.body),
            ]))
            for attention in entry.shelved {
                text.append(NSAttributedString(string: " ●", attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: attention == .none
                        ? Theme.chromeMutedText
                        : Theme.attentionColor(attention),
                    .baselineOffset: 1.5,
                ]))
            }
        }
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
        if parseRemoteQuery(query) == nil, let pathItems = pathModeItems(for: query) {
            summon.setItems(pathItems)
            return
        }
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
        // Bare-word folder completion (`ide repos…`): anchor children whose
        // names start with the query join the offer *below* every project
        // match — projects outrank plain folders.
        items += folderSuggestions(for: query, excluding: Set(entries.map(\.path)))
        summon.setItems(items)
    }

    // MARK: Path mode

    /// A leading `/` or `~` turns the query into a filesystem walk: the offer
    /// becomes the typed directory's children instead of the repo scan.
    /// A path that doesn't exist root-anchored resolves against the landing
    /// terminal's cwd, then home — the summon extends the terminal below it,
    /// so `/atelier` reaches `<cwd>/atelier` and the leading slash never
    /// costs a `~`. `/repositories/ate` narrows to the prefix-matching
    /// children, and selecting any row opens it like a scanned entry. Rows
    /// carry the live query as their matchText — like the `host:dir` row,
    /// they're *made* for this query, not matched against it.
    private func pathModeItems(for query: String) -> [SummonItem]? {
        let q = query.trimmingCharacters(in: .whitespaces)
        // Any slash (or `~`) makes the query a path; a colon means host:dir,
        // which is never a local walk.
        guard q.contains("/") || q.hasPrefix("~"), !q.contains(":") else { return nil }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let anchors = [liveCwd?() ?? defaultFolder, home]

        func existingDirs(_ path: String) -> [String] {
            var out: [String] = []
            var isDir: ObjCBool = false
            func offer(_ p: String) {
                guard !out.contains(p),
                      fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { return }
                out.append(p)
            }
            if path.hasPrefix("/") {
                offer(path)
                for anchor in anchors where !path.hasPrefix(anchor) {
                    offer(anchor + path)
                }
            } else {
                // Relative (`repositories/ate`): the terminal's cwd, then home
                // — never the process's own working directory.
                for anchor in anchors { offer("\(anchor)/\(path)") }
            }
            return out
        }

        func directoryChildren(of dir: String, hiddenAllowed: Bool) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .filter { name in
                    // Dotfolders stay hidden unless the filter asks for them.
                    guard hiddenAllowed || !name.hasPrefix(".") else { return false }
                    var isDir: ObjCBool = false
                    return fm.fileExists(atPath: "\(dir)/\(name)", isDirectory: &isDir) && isDir.boolValue
                }
        }

        // Completion semantics, not palette semantics: prefix first, and only
        // when nothing starts with the fragment does subsequence rescue it.
        func matches(in children: [String], filter: String) -> [String] {
            guard !filter.isEmpty else { return children }
            let prefixed = children.filter { $0.lowercased().hasPrefix(filter) }
            return prefixed.isEmpty
                ? children.filter { fuzzyMatches(query: filter, candidate: $0.lowercased()) }
                : prefixed
        }

        // Every interpretation of the typed path, most-literal first: the path
        // as a directory, then its parent + last-component filter — each with
        // its home-relative twin, so `/reposit` reaches ~/repositories even
        // though `/` exists literally. First interpretation with matches wins.
        let expanded = ((q.hasPrefix("~") ? home + q.dropFirst() : q) as NSString).standardizingPath
        var candidates: [(dir: String, filter: String)] =
            existingDirs(expanded).map { ($0, "") }
        let fragment = (expanded as NSString).lastPathComponent.lowercased()
        candidates += existingDirs((expanded as NSString).deletingLastPathComponent)
            .map { ($0, fragment) }

        var dir = candidates.first?.dir ?? home
        var matched: [String] = []
        for candidate in candidates {
            let children = directoryChildren(
                of: candidate.dir, hiddenAllowed: candidate.filter.hasPrefix(".")
            )
            matched = matches(in: children, filter: candidate.filter)
            if !matched.isEmpty {
                dir = candidate.dir
                break
            }
        }

        let matchText = q.lowercased()
        return matched.map { pathItem(dir: dir, name: $0, matchText: matchText) }
    }

    /// A folder row: name mono, containing dir muted, `⇥` completing to the
    /// `~`-shortened path with a trailing `/` so the walk continues.
    private func pathItem(dir: String, name: String, matchText: String? = nil) -> SummonItem {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: name, attributes: [
            .font: Theme.Typography.mono(Theme.Typography.body, weight: .medium),
            .foregroundColor: Theme.chromeText,
        ]))
        text.append(NSAttributedString(string: "  " + dir.replacingOccurrences(of: home, with: "~"), attributes: [
            .font: Theme.Typography.mono(Theme.Typography.small),
            .foregroundColor: Theme.chromeMutedText,
        ]))
        let path = "\(dir)/\(name)"
        return SummonItem(
            id: path,
            text: text,
            matchText: matchText ?? name.lowercased(),
            chord: nil,
            fill: path.replacingOccurrences(of: home, with: "~") + "/"
        )
    }

    /// Bare-word completion, the `ide repos…` gesture: anchor-directory
    /// children whose names start with the query, offered beneath the project
    /// matches. Prefix only — a bare word should complete like a shell, not
    /// pattern-match the whole disk.
    private func folderSuggestions(for query: String, excluding taken: Set<String>) -> [SummonItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !q.contains("/"), !q.contains(":"), !q.hasPrefix("~") else { return [] }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var seen = taken
        var out: [SummonItem] = []
        for anchor in [liveCwd?() ?? defaultFolder, home] {
            let children = ((try? fm.contentsOfDirectory(atPath: anchor)) ?? [])
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for name in children where name.lowercased().hasPrefix(q) && !name.hasPrefix(".") {
                let path = "\(anchor)/\(name)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
                      seen.insert(path).inserted else { continue }
                out.append(pathItem(dir: anchor, name: name))
            }
        }
        return Array(out.prefix(8))
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

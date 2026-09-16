import AppKit
import CoreServices

/// The editor's file tree (M2.6) — the VSCode Explorer instinct. Rooted at
/// the session's directory and always in view down the editor pane's left
/// edge, so the pane opens onto the repo instead of onto an empty well.
///
/// Reads the filesystem lazily (children on first expand), hides `.git`,
/// and dims what `.gitignore` excludes the way VSCode does. Single click on
/// a file *previews* it (soft-wrapped, focus stays here); double
/// click or `↩` *commits* — the buffer opens for real and the tree folds to
/// a thin rail whose chevron brings it back. Folders toggle on click. An
/// FSEvents stream on the root keeps the tree honest while the agent and
/// shell write files — expansion and selection survive the reload.
final class FileExplorerView: NSView {
    static let width: CGFloat = 220
    static let railWidth: CGFloat = 26

    /// A file was chosen. `commit` is false for a single click (preview),
    /// true for double click / `↩` (open for real).
    var onOpen: ((URL, _ commit: Bool) -> Void)?
    /// The chevron — rail wants to expand, header wants to fold.
    var onToggle: (() -> Void)?

    /// Where a top-level row's disclosure chevron is centred, in the outline's
    /// x — the indent guides and sticky rows key off it.
    static let chevronCenterX: CGFloat = 8

    /// Sticky folder headers (VSCode's sticky scroll): the ancestor chain of
    /// the row scrolled under the top edge stays pinned there, so you always
    /// know which folder you're inside. Click one to jump back to it.
    private let sticky = StickyFolderStack()

    /// Folded to the rail: only the chevron shows.
    private(set) var isCollapsed = false
    private let header = NSView()
    private let rootLabel = NSTextField(labelWithString: "")
    private let chevron = HoverPadButton(frame: .zero)
    /// Collapsed: the entire rail answers a click; the chevron rides at its
    /// top, centred in the rail's width.
    private let rail = HoverPadButton(frame: .zero)
    private let railChevron = NSImageView()

    /// A text hit was chosen (search bar, Text mode): open at the hit.
    var onOpenAt: ((URL, SearchHit) -> Void)?
    /// Arrowing through search results: preview this one (file, or file at
    /// a text hit) without leaving the field.
    var onPreview: ((URL, SearchHit?) -> Void)?

    /// The search panel (VSCode's Go to File and Find in Files, given a home
    /// in the sidebar). Opened by the header's magnifier or ⌘⇧E, it takes
    /// the tree's place: two independent toggles — Files (the ⌘P offer) and
    /// Text (the ⌘⇧F ripgrep engine) — over one summon list, both on by
    /// default (owner call): file matches land at once, text hits follow
    /// beneath them as two-line rows. `↩`/click opens for real (Text: at the
    /// hit); `Esc` clears the query, then closes.
    private let magnifier = HoverPadButton(frame: .zero)
    private let searchHost = NSView()
    private var searchHostHeight: NSLayoutConstraint!
    private let modeControl = NSSegmentedControl(labels: ["Files", "Text"], trackingMode: .selectAny, target: nil, action: nil)
    private let search = SummonList(style: .init(
        placeholder: "Search",
        fieldFont: Theme.Typography.mono(Theme.Typography.small),
        placeholderFont: Theme.Typography.ui(Theme.Typography.small),
        rowHeight: 22,
        rowInset: 8,
        noMatchText: "No matches",
        escClearsQueryFirst: true,
        filtersLocally: false,
        detailRowHeight: 36
    ))
    private var textEngine: RepoTextSearch?
    private var fileOffer: [SummonItem] = []
    private var fileRows: [SummonItem] = []
    private var textRows: [SummonItem] = []
    private var liveQuery = ""
    private(set) var isSearchOpen = false
    private static let filesKey = "explorer.search.files"
    private static let textKey = "explorer.search.text"
    private var filesOn: Bool {
        get { UserDefaults.standard.object(forKey: Self.filesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.filesKey) }
    }
    private var textOn: Bool {
        get { UserDefaults.standard.object(forKey: Self.textKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.textKey) }
    }
    /// Files rows are capped while a query is live so text hits stay in reach.
    private static let fileRowCap = 40

    private(set) var root: String?
    private var rootNode: FileNode?
    private let outline = NSOutlineView()
    private let scroll = NSScrollView()
    private var ignored: Set<String> = []
    private var stream: FSEventStreamRef?
    private var reloadDebounce: Timer?
    /// The open file's path — the row the tree keeps selected.
    private var revealedPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
        build()
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
        stopWatching()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { window?.makeFirstResponder(outline) ?? false }
    var focusView: NSView { outline }

    func setCollapsed(_ collapsed: Bool) {
        guard collapsed != isCollapsed else { return }
        isCollapsed = collapsed
        if collapsed, isSearchOpen { closeSearch(focusTree: false) }
        scroll.isHidden = collapsed || isSearchOpen
        header.isHidden = collapsed
        searchHost.isHidden = collapsed
        rail.isHidden = !collapsed
        railChevron.isHidden = !collapsed
    }

    private static func chevronImage(_ name: String) -> NSImage? { symbol(name, size: 10) }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(.init(paletteColors: [Theme.chromeText]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    @objc private func chevronClicked() { onToggle?() }

    @objc private func appearanceChanged() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.crust.cgColor
    }

    private func build() {
        let column = NSTableColumn(identifier: .init("name"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .regular
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.rowHeight = 22
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.indentationPerLevel = 12
        outline.indentationMarkerFollowsCell = true
        outline.autoresizesOutlineColumn = true
        outline.floatsGroupRows = false
        outline.focusRingType = .none
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(rowClicked)
        outline.doubleAction = #selector(rowDoubleClicked)

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.backgroundColor = .clear
        scroll.contentView.drawsBackground = false
        scroll.scrollerStyle = .overlay
        scroll.contentInsets = NSEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(treeScrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView
        )
        sticky.translatesAutoresizingMaskIntoConstraints = false
        sticky.isHidden = true
        sticky.onJump = { [weak self] node in
            guard let self else { return }
            let row = self.outline.row(forItem: node)
            guard row >= 0 else { return }
            let rect = self.outline.rect(ofRow: row)
            self.scroll.contentView.scroll(to: NSPoint(x: 0, y: rect.minY - self.scroll.contentInsets.top))
            self.scroll.reflectScrolledClipView(self.scroll.contentView)
        }
        addSubview(scroll)

        addSubview(sticky)

        // The hairline that seats the tree beside the buffer.
        let edge = NSView()
        edge.wantsLayer = true
        edge.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        edge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(edge)

        // Header: the root's name (small, muted) and the fold chevron. In the
        // rail only the chevron survives.
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        rootLabel.font = Theme.Typography.ui(Theme.Typography.small, weight: .medium)
        rootLabel.textColor = Theme.chromeMutedText
        rootLabel.lineBreakMode = .byTruncatingTail
        rootLabel.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(rootLabel)
        chevron.image = Self.chevronImage("chevron.left")
        chevron.toolTip = "Hide Explorer (⌘B)"
        chevron.target = self
        chevron.action = #selector(chevronClicked)
        chevron.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(chevron)
        magnifier.image = Self.symbol("magnifyingglass", size: 11)
        magnifier.toolTip = "Search files and text (⌘⇧E)"
        magnifier.target = self
        magnifier.action = #selector(magnifierClicked)
        magnifier.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(magnifier)

        // Search panel: hidden (0pt) until opened; then it takes the tree's
        // place under the header. Both summons live in it, one visible.
        searchHost.wantsLayer = true
        searchHost.layer?.masksToBounds = true
        searchHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchHost)
        modeControl.controlSize = .small
        modeControl.font = Theme.Typography.ui(Theme.Typography.small)
        modeControl.segmentStyle = .roundRect
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        searchHost.addSubview(modeControl)
        search.translatesAutoresizingMaskIntoConstraints = false
        search.onEscape = { [weak self] in self?.closeSearch(focusTree: true) }
        search.onQueryChange = { [weak self] query in self?.runSearch(query) }
        search.onArrowSelect = { [weak self] item in
            guard let self, let root = self.root else { return }
            if let found = RepoTextSearch.location(of: item, root: root) {
                self.onPreview?(found.url, found.hit)
            } else if item.id != RepoTextSearch.moreRowId {
                self.onPreview?(URL(fileURLWithPath: item.id), nil)
            }
        }
        search.onActivate = { [weak self] item in
            guard let self, let root = self.root else { return }
            if let found = RepoTextSearch.location(of: item, root: root) {
                self.closeSearch(focusTree: false)
                self.onOpenAt?(found.url, found.hit)
            } else if item.id != RepoTextSearch.moreRowId {
                RecentFilesStore.record(item.id, root: root)
                self.closeSearch(focusTree: false)
                self.onOpen?(URL(fileURLWithPath: item.id), true)
            }
        }
        searchHost.addSubview(search)
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: -6),
            search.leadingAnchor.constraint(equalTo: searchHost.leadingAnchor),
            search.trailingAnchor.constraint(equalTo: searchHost.trailingAnchor),
            search.bottomAnchor.constraint(equalTo: searchHost.bottomAnchor),
        ])

        // The rail: one tall button under a chevron glyph that lets clicks
        // through to it. Hidden until the tree folds.
        railChevron.image = Self.chevronImage("chevron.right")
        railChevron.imageScaling = .scaleNone
        railChevron.translatesAutoresizingMaskIntoConstraints = false
        rail.toolTip = "Show Explorer (⌘B)"
        rail.target = self
        rail.action = #selector(chevronClicked)
        rail.layer?.cornerRadius = 0
        rail.translatesAutoresizingMaskIntoConstraints = false
        rail.isHidden = true
        railChevron.isHidden = true
        addSubview(rail)
        addSubview(railChevron)

        searchHostHeight = searchHost.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            railChevron.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            railChevron.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            railChevron.widthAnchor.constraint(equalToConstant: 14),
            railChevron.heightAnchor.constraint(equalToConstant: 14),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            header.heightAnchor.constraint(equalToConstant: 26),
            chevron.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 3),
            chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 20),
            chevron.heightAnchor.constraint(equalToConstant: 20),
            rootLabel.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: 4),
            rootLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            magnifier.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -4),
            magnifier.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            magnifier.widthAnchor.constraint(equalToConstant: 20),
            magnifier.heightAnchor.constraint(equalToConstant: 20),
            rootLabel.trailingAnchor.constraint(lessThanOrEqualTo: magnifier.leadingAnchor, constant: -6),
            searchHost.topAnchor.constraint(equalTo: header.bottomAnchor),
            searchHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            searchHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            searchHostHeight,
            modeControl.topAnchor.constraint(equalTo: searchHost.topAnchor, constant: 4),
            modeControl.leadingAnchor.constraint(equalTo: searchHost.leadingAnchor, constant: 10),
            sticky.topAnchor.constraint(equalTo: searchHost.bottomAnchor),
            sticky.leadingAnchor.constraint(equalTo: leadingAnchor),
            sticky.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            scroll.topAnchor.constraint(equalTo: searchHost.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: edge.leadingAnchor),
            edge.topAnchor.constraint(equalTo: topAnchor),
            edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: trailingAnchor),
            edge.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    // MARK: Root

    /// Point the tree at `root`. Same root is a no-op; a new one rebuilds.
    func setRoot(_ root: String) {
        guard root != self.root else { return }
        stopWatching()
        self.root = root
        rootNode = FileNode(path: root, isDirectory: true)
        rootLabel.stringValue = (root as NSString).lastPathComponent
        textEngine = RepoTextSearch(root: root)
        closeSearch(focusTree: false)
        refreshOffer()
        ignored = []
        outline.reloadData()
        refreshIgnored()
        startWatching(root)
    }

    /// Select the row for `path`, expanding the folders above it. Silent if
    /// the path isn't under the root. `scroll` brings the row into view — an
    /// open does that, a background reload must not yank the list around.
    func reveal(path: String, scroll: Bool = true) {
        revealedPath = path
        guard let root, path.hasPrefix(root + "/") else { return }
        let rel = String(path.dropFirst(root.count + 1)).split(separator: "/").map(String.init)
        var node = rootNode
        var walked = root
        for component in rel.dropLast() {
            walked += "/" + component
            guard let child = node?.children(hidingIgnored: false).first(where: { $0.path == walked }) else { return }
            outline.expandItem(child)
            node = child
        }
        guard let leaf = node?.children(hidingIgnored: false).first(where: { $0.path == path }) else { return }
        let row = outline.row(forItem: leaf)
        guard row >= 0 else { return }
        outline.selectRowIndexes([row], byExtendingSelection: false)
        if scroll { outline.scrollRowToVisible(row) }
    }


    /// Dev-only (snapshots): geometry of the sidebar's parts.
    var debugGeometry: String {
        "explorer bounds=\(bounds.size) collapsed=\(isCollapsed) searchOpen=\(isSearchOpen) files=\(filesOn) text=\(textOn) "
            + "header=\(header.frame) host=\(searchHost.frame) search=\(search.frame) rows=\(fileRows.count)+\(textRows.count) "
            + "tree=\(scroll.frame) treeHidden=\(scroll.isHidden) sticky=\(sticky.frame) stickyHidden=\(sticky.isHidden) "
            + "clipY=\(scroll.contentView.bounds.minY) topRow=\(outline.row(at: NSPoint(x: 1, y: scroll.contentView.bounds.minY + 1)))"
    }

    /// Dev-only (snapshots): open the panel and type `query`; trailing `↓`
    /// characters are arrow presses (they arrive after the text search
    /// lands, so the row set is the real one).
    func debugSetQuery(_ query: String) {
        // `tree:expand=a,b/c;scroll=300` — drive the tree instead.
        if query.hasPrefix("tree:") {
            closeSearch(focusTree: false)
            for part in query.dropFirst(5).split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2, let root else { continue }
                if kv[0] == "expand" {
                    for rel in kv[1].split(separator: ",") {
                        var node = rootNode
                        var walked = root
                        for component in rel.split(separator: "/") {
                            walked += "/" + component
                            node = node?.children(hidingIgnored: false).first { $0.path == walked }
                            if let node { outline.expandItem(node) }
                        }
                    }
                } else if kv[0] == "scroll", let y = Double(kv[1]) {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
            }
            return
        }
        openSearch()
        let downs = query.reversed().prefix { $0 == "↓" }.count
        search.setQuery(String(query.dropLast(downs)))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            for _ in 0..<downs { self?.search.debugMoveDown() }
        }
    }

    // MARK: Search panel

    @objc private func magnifierClicked() {
        if isSearchOpen { closeSearch(focusTree: true) } else { openSearch() }
    }

    @objc private func modeChanged() {
        filesOn = modeControl.isSelected(forSegment: 0)
        textOn = modeControl.isSelected(forSegment: 1)
        runSearch(liveQuery)
        window?.makeFirstResponder(search.focusField)
    }

    /// Open the panel (⌘⇧E / the magnifier). The tree steps aside; the
    /// field takes focus; the offer is what the toggles say.
    func openSearch() {
        guard root != nil else { return }
        // The button now means "back to the tree".
        magnifier.image = Self.symbol("list.bullet.indent", size: 11)
        magnifier.toolTip = "Back to files (Esc)"
        modeControl.setSelected(filesOn, forSegment: 0)
        modeControl.setSelected(textOn, forSegment: 1)
        isSearchOpen = true
        scroll.isHidden = true
        searchHostHeight.constant = max(0, bounds.height - header.frame.height)
        layoutSubtreeIfNeeded()
        runSearch(search.query)
        window?.makeFirstResponder(search.focusField)
    }

    /// Close the panel: query cleared, tree back, focus to it if asked.
    func closeSearch(focusTree: Bool) {
        magnifier.image = Self.symbol("magnifyingglass", size: 11)
        magnifier.toolTip = "Search files and text (⌘⇧E)"
        search.clearQuery()
        textRows = []
        guard isSearchOpen else { return }
        isSearchOpen = false
        searchHostHeight.constant = 0
        scroll.isHidden = isCollapsed
        layoutSubtreeIfNeeded()
        if focusTree { window?.makeFirstResponder(outline) }
    }

    /// One query, two sources. Files filter locally and land at once (the
    /// whole offer when the field is empty — a browsable list); text hits
    /// arrive from ripgrep a beat later and append. Stale text results for
    /// an older query are dropped.
    private func runSearch(_ query: String) {
        liveQuery = query
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if filesOn {
            if q.isEmpty {
                fileRows = fileOffer
            } else {
                fileRows = fileOffer
                    .filter { fuzzyMatches(query: q, candidate: $0.matchText) }
                    .enumerated()
                    .sorted { a, b in
                        let ra = RepoFileOffer.rank(a.element, q), rb = RepoFileOffer.rank(b.element, q)
                        return ra != rb ? ra > rb : a.offset < b.offset
                    }
                    .prefix(Self.fileRowCap)
                    .map(\.element)
            }
        } else {
            fileRows = []
        }
        textRows = []
        publishRows()
        guard textOn, !q.isEmpty, let engine = textEngine else { return }
        engine.search(query, compact: true) { [weak self] items in
            guard let self, self.liveQuery == query else { return }
            self.textRows = items
            self.publishRows()
        }
    }

    private func publishRows() {
        search.setItems(fileRows + textRows)
    }

    override func layout() {
        super.layout()
        if isSearchOpen {
            let target = max(0, bounds.height - header.frame.height)
            if searchHostHeight.constant != target { searchHostHeight.constant = target }
        }
    }

    /// Refill the search offer from `git ls-files` — on root change and on
    /// every tree reload (a new file should be findable at once).
    private func refreshOffer() {
        guard let root else { return }
        RepoFileOffer.gather(root: root, rowFont: Theme.Typography.small) { [weak self] items in
            guard let self, self.root == root else { return }
            self.fileOffer = items
            if self.isSearchOpen { self.runSearch(self.liveQuery) }
        }
    }

    // MARK: Sticky folders

    @objc private func treeScrolled() { updateSticky() }

    /// The ancestors of the row under the sticky stack, root-most first.
    /// Two passes: the stack's own height changes which row is "under" it.
    private func updateSticky() {
        guard !scroll.isHidden, rootNode != nil else { sticky.isHidden = true; return }
        let rowHeight = outline.rowHeight
        func ancestors(under stackHeight: CGFloat) -> [FileNode] {
            let y = scroll.contentView.bounds.minY + stackHeight + 1
            let row = outline.row(at: NSPoint(x: 1, y: y))
            guard row >= 0, let item = outline.item(atRow: row) else { return [] }
            var chain: [FileNode] = []
            var node: Any? = outline.parent(forItem: item)
            while let parent = node as? FileNode {
                chain.insert(parent, at: 0)
                node = outline.parent(forItem: parent)
            }
            // A folder whose own row is still visible below the stack doesn't
            // need pinning yet.
            return chain.filter { outline.rect(ofRow: outline.row(forItem: $0)).minY < y }
        }
        var chain = ancestors(under: 0)
        chain = ancestors(under: CGFloat(chain.count) * rowHeight)
        guard !chain.isEmpty, scroll.contentView.bounds.minY > -scroll.contentInsets.top + 1 else {
            sticky.isHidden = true
            return
        }
        sticky.isHidden = false
        sticky.show(chain.map { node in
            (node, outline.level(forItem: node), isIgnored(node.path))
        }, rowHeight: rowHeight, step: outline.indentationPerLevel)
    }

    // MARK: Actions

    @objc private func rowClicked() {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
            // Folders don't own the selection; the open file does.
            if let revealedPath { reveal(path: revealedPath, scroll: false) } else { outline.deselectAll(nil) }
        } else {
            onOpen?(URL(fileURLWithPath: node.path), false)
        }
    }

    @objc private func rowDoubleClicked() {
        let row = outline.clickedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode, !node.isDirectory else { return }
        onOpen?(URL(fileURLWithPath: node.path), true)
    }

    private func openSelected(commit: Bool) {
        let row = outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            if outline.isItemExpanded(node) { outline.collapseItem(node) } else { outline.expandItem(node) }
        } else {
            onOpen?(URL(fileURLWithPath: node.path), commit)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: openSelected(commit: true) // ↩ / keypad ↩
        default: super.keyDown(with: event)
        }
    }

    // MARK: Ignore state

    /// One `git status --ignored` per reload: entries come back as
    /// `!! path` (directories collapsed with a trailing slash), and a path is
    /// dimmed when it or any ancestor is listed. Untracked-but-not-ignored
    /// stays bright — those are the files you're making.
    private func refreshIgnored() {
        guard let root else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", root, "status", "--porcelain", "--ignored", "-z", "--untracked-files=normal"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var set: Set<String> = []
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let entries = (String(data: data, encoding: .utf8) ?? "").split(separator: "\0")
                for entry in entries where entry.hasPrefix("!! ") {
                    var rel = String(entry.dropFirst(3))
                    if rel.hasSuffix("/") { rel.removeLast() }
                    set.insert(root + "/" + rel)
                }
            }
            DispatchQueue.main.async {
                guard let self, self.root == root else { return }
                self.ignored = set
                self.outline.reloadData()
                if let revealedPath = self.revealedPath { self.reveal(path: revealedPath, scroll: false) }
            }
        }
    }

    private func isIgnored(_ path: String) -> Bool {
        guard let root, !ignored.isEmpty else { return false }
        var walk = path
        while walk.count > root.count {
            if ignored.contains(walk) { return true }
            guard let slash = walk.lastIndex(of: "/") else { break }
            walk = String(walk[..<slash])
        }
        return false
    }

    // MARK: Watching

    private func startWatching(_ root: String) {
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let view = Unmanaged<FileExplorerView>.fromOpaque(info).takeUnretainedValue()
            // `.git` churns constantly — and our own `git status` refreshes
            // the index, which would otherwise reload the tree in a loop.
            guard let changed = unsafeBitCast(paths, to: CFArray.self) as? [String],
                  let root = view.root else { return }
            let gitDir = root + "/.git"
            let relevant = changed.prefix(Int(count)).contains { !$0.hasPrefix(gitDir) }
            if relevant { view.scheduleReload() }
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagIgnoreSelf | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleReload() {
        reloadDebounce?.invalidate()
        reloadDebounce = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
            self?.reload()
        }
    }

    /// Drop every cached listing and reload. Nodes compare by path, so the
    /// outline keeps expanded folders expanded; the open file re-selects.
    private func reload() {
        rootNode?.invalidateDeep()
        outline.reloadData()
        updateSticky()
        if let revealedPath { reveal(path: revealedPath, scroll: false) }
        refreshIgnored()
        refreshOffer()
    }
}

// MARK: - Data source / delegate

extension FileExplorerView: NSOutlineViewDataSource, NSOutlineViewDelegate {
    private func node(_ item: Any?) -> FileNode? {
        item == nil ? rootNode : item as? FileNode
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(item)?.children(hidingIgnored: false).count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(item)!.children(hidingIgnored: false)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let row = ExplorerRowView()
        row.depth = outlineView.level(forItem: item)
        row.guideStep = outlineView.indentationPerLevel
        return row
    }

    func outlineViewItemDidExpand(_ notification: Notification) { updateSticky() }
    func outlineViewItemDidCollapse(_ notification: Notification) { updateSticky() }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? ExplorerCellView) ?? ExplorerCellView(identifier: id)
        cell.configure(name: node.name, isDirectory: node.isDirectory, dimmed: isIgnored(node.path))
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool { true }
}

// MARK: - Nodes

/// One entry in the tree. `NSObject` so the outline's expansion bookkeeping
/// (which hashes items) survives `reloadData` — equality is by path.
final class FileNode: NSObject {
    let path: String
    let name: String
    let isDirectory: Bool
    private var cached: [FileNode]?

    init(path: String, isDirectory: Bool) {
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.isDirectory = isDirectory
    }

    override var hash: Int { path.hashValue }
    override func isEqual(_ object: Any?) -> Bool { (object as? FileNode)?.path == path }

    /// Folders first, then files, each case-insensitively by name. `.git`
    /// stays out of the tree; every other dotfile is yours to see.
    func children(hidingIgnored: Bool) -> [FileNode] {
        guard isDirectory else { return [] }
        if let cached { return cached }
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        var dirs: [FileNode] = []
        var files: [FileNode] = []
        for name in names where name != ".git" {
            let child = path + "/" + name
            var isDir: ObjCBool = false
            fm.fileExists(atPath: child, isDirectory: &isDir)
            let node = FileNode(path: child, isDirectory: isDir.boolValue)
            if isDir.boolValue { dirs.append(node) } else { files.append(node) }
        }
        let byName: (FileNode, FileNode) -> Bool = {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let result = dirs.sorted(by: byName) + files.sorted(by: byName)
        cached = result
        return result
    }

    /// Forget listings all the way down; the next ask re-reads the disk.
    func invalidateDeep() {
        cached?.forEach { $0.invalidateDeep() }
        cached = nil
    }
}

// MARK: - Rows and cells

/// Selection as a soft surface0 pad, inset like the tab chips — never the
/// system accent.
private final class ExplorerRowView: NSTableRowView {
    /// Nesting level; one indent guide per ancestor.
    var depth = 0
    var guideStep: CGFloat = 12

    /// The pane's crust shows through; the only paint is the indent guides —
    /// a hairline under each ancestor's chevron, so a folder's extent reads
    /// as a vertical line down its children (owner ask 2026-09-15).
    override func drawBackground(in dirtyRect: NSRect) {} // AppKit skips this on a clear table anyway
    override func draw(_ dirtyRect: NSRect) {
        if depth > 0 {
            Theme.Elevation.hairline.setFill()
            for level in 0..<depth {
                let x = FileExplorerView.chevronCenterX + guideStep * CGFloat(level)
                NSRect(x: x - 0.5, y: 0, width: 1, height: bounds.height).fill()
            }
        }
        super.draw(dirtyRect)
    }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 6, dy: 1)
        Theme.Elevation.surface0.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Theme.Elevation.radiusSmall, yRadius: Theme.Elevation.radiusSmall).fill()
    }
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

private final class ExplorerCellView: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.font = Theme.Typography.ui(Theme.Typography.body)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(label)
        textField = label
        imageView = icon
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(name: String, isDirectory: Bool, dimmed: Bool) {
        label.stringValue = name
        let color = dimmed ? Theme.chromeMutedText : Theme.chromeText
        label.textColor = color
        let symbol = isDirectory ? "folder" : "doc"
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(.init(paletteColors: [Theme.chromeMutedText]))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        icon.alphaValue = dimmed ? 0.6 : 1
    }
}


// MARK: - Sticky folder stack

/// The pinned ancestor rows over the tree. Each row mirrors the tree's own
/// cell — chevron (open), folder glyph, name — at the same indentation, on
/// the pane's crust with a hairline beneath, so it reads as the tree
/// having stuck rather than a separate toolbar.
private final class StickyFolderStack: NSView {
    var onJump: ((FileNode) -> Void)?
    private var rows: [StickyRow] = []
    private let hairline = NSView()
    private var heightConstraint: NSLayoutConstraint!

    /// Opaque crust: the rows scroll on underneath, and a translucent strip
    /// would show their text through the pinned names. The one place the
    /// sidebar gives up its blur, on purpose.
    private static var fill: CGColor { Theme.Elevation.crust.withAlphaComponent(1).cgColor }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Self.fill
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = Theme.Elevation.hairline.cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)
        heightConstraint = heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            heightConstraint,
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: bottomAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateLayer() {
        layer?.backgroundColor = Self.fill
    }

    func show(_ chain: [(node: FileNode, level: Int, dimmed: Bool)], rowHeight: CGFloat, step: CGFloat) {
        while rows.count < chain.count {
            let row = StickyRow(frame: .zero)
            row.onClick = { [weak self] node in self?.onJump?(node) }
            addSubview(row, positioned: .below, relativeTo: hairline)
            rows.append(row)
        }
        for (index, row) in rows.enumerated() {
            guard index < chain.count else { row.isHidden = true; continue }
            row.isHidden = false
            let entry = chain[index]
            row.frame = NSRect(x: 0, y: bounds.height - rowHeight * CGFloat(index + 1), width: bounds.width, height: rowHeight)
            row.autoresizingMask = [.width, .minYMargin]
            row.configure(node: entry.node, level: entry.level, step: step, dimmed: entry.dimmed)
        }
        heightConstraint.constant = rowHeight * CGFloat(chain.count) + 1
        // Re-seat rows after the height change lands.
        layoutSubtreeIfNeeded()
        for (index, row) in rows.enumerated() where index < chain.count {
            row.frame = NSRect(x: 0, y: bounds.height - 1 - rowHeight * CGFloat(index + 1), width: bounds.width, height: rowHeight)
        }
    }
}

private final class StickyRow: NSView {
    var onClick: ((FileNode) -> Void)?
    private var node: FileNode?
    private let chevron = NSImageView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        chevron.imageScaling = .scaleNone
        icon.imageScaling = .scaleProportionallyDown
        label.font = Theme.Typography.ui(Theme.Typography.body)
        label.lineBreakMode = .byTruncatingMiddle
        for view in [chevron, icon, label] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(node: FileNode, level: Int, step: CGFloat, dimmed: Bool) {
        self.node = node
        let muted = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            .applying(.init(paletteColors: [Theme.chromeMutedText]))
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?.withSymbolConfiguration(muted)
        let folder = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            .applying(.init(paletteColors: [Theme.chromeMutedText]))
        icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)?.withSymbolConfiguration(folder)
        label.stringValue = node.name
        label.font = Theme.Typography.ui(Theme.Typography.body)
        label.textColor = dimmed ? Theme.chromeMutedText : Theme.chromeText
        let indent = step * CGFloat(level)
        let midY = bounds.midY
        chevron.frame = NSRect(x: indent + FileExplorerView.chevronCenterX - 7, y: midY - 7, width: 14, height: 14)
        // Mirrors ExplorerCellView: icon 2pt in from the cell's leading edge,
        // label 5pt after it. The cell begins after the chevron column (16pt).
        let cellX = indent + 16
        icon.frame = NSRect(x: cellX + 2, y: midY - 7, width: 14, height: 14)
        label.sizeToFit()
        label.frame = NSRect(x: cellX + 21, y: midY - label.frame.height / 2,
                             width: max(0, bounds.width - cellX - 27), height: label.frame.height)
    }

    override func layout() {
        super.layout()
        if let node { configure(node: node, level: Int((chevron.frame.midX - FileExplorerView.chevronCenterX) / 12), step: 12, dimmed: label.textColor == Theme.chromeMutedText) }
    }

    override func mouseDown(with event: NSEvent) {
        if let node { onClick?(node) }
    }
}

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

    /// Folded to the rail: only the chevron shows.
    private(set) var isCollapsed = false
    private let header = NSView()
    private let rootLabel = NSTextField(labelWithString: "")
    private let chevron = HoverPadButton(frame: .zero)
    /// Collapsed: the entire rail answers a click; the chevron rides at its
    /// top, centred in the rail's width.
    private let rail = HoverPadButton(frame: .zero)
    private let railChevron = NSImageView()

    /// The search bar (VSCode's Go to File, given a home): the shared summon
    /// surface over the repo's file offer. Empty query → the tree shows
    /// beneath it; typing swaps the tree for the match list; `↩`/click opens
    /// for real; `Esc` clears, then returns focus to the tree.
    private let search = SummonList(style: .init(
        placeholder: "Search files",
        fieldFont: Theme.Typography.mono(Theme.Typography.small),
        placeholderFont: Theme.Typography.ui(Theme.Typography.small),
        rowHeight: 22,
        rowInset: 8,
        noMatchText: "No matching files",
        escClearsQueryFirst: true
    ))
    private var searchListHeight: NSLayoutConstraint!
    private var isSearching = false

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
        scroll.isHidden = collapsed || isSearching
        header.isHidden = collapsed
        search.isHidden = collapsed
        rail.isHidden = !collapsed
        railChevron.isHidden = !collapsed
    }

    private static func chevronImage(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
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
        addSubview(scroll)

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

        // Search bar: hugs its field until a query arrives, then the list
        // takes the tree's place.
        search.translatesAutoresizingMaskIntoConstraints = false
        searchListHeight = search.makeListHeightConstraint(constant: 0)
        search.rank = RepoFileOffer.rank
        search.onQueryChange = { [weak self] query in
            guard let self else { return }
            let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
            guard searching != self.isSearching else { return }
            self.isSearching = searching
            self.scroll.isHidden = searching || self.isCollapsed
            self.sizeSearchList()
        }
        search.onActivate = { [weak self] item in
            guard let self, let root = self.root else { return }
            RecentFilesStore.record(item.id, root: root)
            self.search.clearQuery()
            self.onOpen?(URL(fileURLWithPath: item.id), true)
        }
        search.onEscape = { [weak self] in
            guard let self else { return }
            self.search.clearQuery()
            self.window?.makeFirstResponder(self.outline)
        }
        addSubview(search)

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
            rootLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -8),
            rootLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            search.topAnchor.constraint(equalTo: header.bottomAnchor),
            search.leadingAnchor.constraint(equalTo: leadingAnchor),
            search.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            searchListHeight,
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor),
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
        search.clearQuery()
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

    /// Search bar's field — the place ⌃⌘H-then-type wants to land.
    var searchField: NSView { search.focusField }

    /// Dev-only (snapshots): geometry of the sidebar's parts.
    var debugGeometry: String {
        "explorer bounds=\(bounds.size) collapsed=\(isCollapsed) searching=\(isSearching) "
            + "header=\(header.frame) search=\(search.frame) listH=\(searchListHeight.constant) "
            + "tree=\(scroll.frame) treeHidden=\(scroll.isHidden) searchHidden=\(search.isHidden) "
            + "hasAmbiguous=\(search.hasAmbiguousLayout)"
    }

    /// Dev-only (snapshots): put a query in the bar as if typed.
    func debugSetQuery(_ query: String) {
        window?.makeFirstResponder(search.focusField)
        search.setQuery(query)
    }

    /// The list under the search bar sizes to the pane while a query is
    /// live, and to nothing otherwise (the field stays; the tree follows).
    /// The field block's height is measured, not guessed.
    private func sizeSearchList() {
        let fieldBlock = search.frame.height - searchListHeight.constant
        let target = isSearching ? max(0, bounds.height - header.frame.height - fieldBlock) : 0
        guard searchListHeight.constant != target else { return }
        searchListHeight.constant = target
        layoutSubtreeIfNeeded()
    }

    override func layout() {
        super.layout()
        if isSearching { sizeSearchList() }
    }

    /// Refill the search offer from `git ls-files` — on root change and on
    /// every tree reload (a new file should be findable at once).
    private func refreshOffer() {
        guard let root else { return }
        RepoFileOffer.gather(root: root, rowFont: Theme.Typography.small) { [weak self] items in
            guard let self, self.root == root else { return }
            self.search.setItems(items)
        }
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
        ExplorerRowView()
    }

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
    override func drawBackground(in dirtyRect: NSRect) {} // the pane's crust shows through
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

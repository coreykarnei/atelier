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
}

struct LandingEntry {
    let name: String
    let path: String
    let isRecent: Bool
}

/// The landing pane (MILESTONE_1 §2: a session starts as a Landing and is promoted
/// into an IDE session). Shows recent projects plus the repos in the default folder;
/// Enter / double-click promotes the session to the chosen root. The terminal below
/// it is the session's own shell pane — a Landing *is* the "just a terminal" tab.
final class LandingView: NSView, WorkspacePane, NSTableViewDataSource, NSTableViewDelegate {
    /// Called with the chosen project root.
    var onOpen: ((String) -> Void)?

    var focusView: NSView { table }

    private let table = LandingTableView()
    private var entries: [LandingEntry] = []

    init(defaultFolder: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
        entries = Self.entries(defaultFolder: defaultFolder)
        build()
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

    override func updateLayer() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    @objc private func accessibilityDisplayChanged() {
        layer?.backgroundColor = Theme.Elevation.mantle.cgColor
    }

    private func build() {
        let header = NSTextField(labelWithString: "Open a project")
        header.font = Theme.Typography.ui(Theme.Typography.small, weight: .semibold)
        header.textColor = Theme.chromeMutedText
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        let hint = NSTextField(labelWithString: "↩ open · ⌘↩ ide in terminal dir")
        hint.font = Theme.Typography.ui(Theme.Typography.small)
        hint.textColor = Theme.chromeMutedText
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)

        table.dataSource = self
        table.delegate = self
        table.headerView = nil
        table.rowHeight = 24
        table.backgroundColor = .clear
        table.style = .plain
        table.allowsEmptySelection = false
        table.doubleAction = #selector(rowDoubleClicked)
        table.target = self
        table.onReturn = { [weak self] in self?.openSelected() }
        let column = NSTableColumn(identifier: .init("entry"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            hint.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        if entries.isEmpty {
            // First-launch empty state (§5): one designed two-voice line, not
            // a blank list. Atelier speaks SF Pro; `cd` and the chord are mono.
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
                hint.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            table.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    /// Recents (that still exist) first, then git repos in the default folder.
    static func entries(defaultFolder: String) -> [LandingEntry] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [LandingEntry] = []

        for path in RecentsStore.all() where fm.fileExists(atPath: path) {
            guard seen.insert(path).inserted else { continue }
            out.append(LandingEntry(name: (path as NSString).lastPathComponent, path: path, isRecent: true))
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
        return out
    }

    private func openSelected() {
        guard entries.indices.contains(table.selectedRow) else { return }
        onOpen?(entries[table.selectedRow].path)
    }

    @objc private func rowDoubleClicked() { openSelected() }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = (entry.path as NSString).deletingLastPathComponent
            .replacingOccurrences(of: home, with: "~")

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
        text.append(NSAttributedString(string: "  \(dir)", attributes: [
            .font: Theme.Typography.mono(Theme.Typography.small),
            .foregroundColor: Theme.chromeMutedText,
        ]))

        let label = NSTextField(labelWithAttributedString: text)
        label.lineBreakMode = .byTruncatingTail
        let cell = NSTableCellView()
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// NSTableView that reports Return as "open" instead of beeping.
private final class LandingTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { // Return
            onReturn?()
            return
        }
        super.keyDown(with: event)
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

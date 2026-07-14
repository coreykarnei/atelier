import AppKit

/// One palette entry. `key` is the display chord (the palette teaches the keymap).
struct PaletteCommand {
    let id: String
    let title: String
    let key: String?
    let action: () -> Void
}

/// Recently run command ids — they float to the top of the palette.
private enum RecentCommands {
    private static let key = "palette.recents"

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func bump(_ id: String) {
        var list = all().filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(10)), forKey: key)
    }
}

/// The command palette (MILESTONE_1 §8): the discoverable backstop for every
/// action. A `SummonCardOverlay` whose offer is the curated command set; the
/// dedicated fast paths (⌘P, ⌘⇧F, the fan) stay separate.
final class CommandPalette: SummonCardOverlay {
    private let commands: [PaletteCommand]

    init(commands: [PaletteCommand], onDismiss: @escaping () -> Void) {
        let recents = RecentCommands.all()
        // Recents first (most recent leading), then declaration order.
        self.commands = commands.sorted { a, b in
            let ra = recents.firstIndex(of: a.id) ?? Int.max
            let rb = recents.firstIndex(of: b.id) ?? Int.max
            return ra != rb ? ra < rb
                : commands.firstIndex(where: { $0.id == a.id })! < commands.firstIndex(where: { $0.id == b.id })!
        }
        super.init(
            summonStyle: .init(
                placeholder: "Type a command…",
                fieldFont: Theme.Typography.ui(Theme.Typography.large),
                placeholderFont: nil,
                rowHeight: 28,
                rowInset: 14,
                noMatchText: "No matching commands",
                escClearsQueryFirst: false
            ),
            onDismiss: onDismiss
        )

        summon.onActivate = { [weak self] item in self?.run(at: Int(item.id) ?? -1) }
        // Items are keyed by position, not command id — dynamic commands can
        // collide on id (two projects with the same window title), and the row
        // the user picked must be the row that runs.
        summon.setItems(self.commands.enumerated().map { index, command in
            SummonItem(
                id: String(index),
                // Command names are Atelier speaking (§1.4); chords are keycaps.
                text: NSAttributedString(string: command.title, attributes: [
                    .font: Theme.Typography.ui(Theme.Typography.body),
                    .foregroundColor: Theme.chromeText,
                ]),
                matchText: command.title.lowercased(),
                chord: command.key
            )
        })
    }

    private func run(at index: Int) {
        guard commands.indices.contains(index) else { return }
        let command = commands[index]
        RecentCommands.bump(command.id)
        dismiss()
        command.action()
    }
}

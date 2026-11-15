import AppKit

/// The glyphs for the editor's slot (2026-11-15): the terminal mark, with a
/// `+` laid over its corner while reaching for it would start a new shell,
/// and the editor's mark for the way back. Template images — the button's
/// tint colours them.
enum SlotGlyph {
    /// The terminal. `adding`: no second shell is running yet, so the click
    /// makes one — the plus says so, cut clear of the frame by a halo, the
    /// `⎇+`'s construction.
    static func terminal(adding: Bool) -> NSImage {
        let symbol = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10.5, weight: .semibold))
        guard adding, let symbol else { return template(symbol) }
        let size = NSSize(width: symbol.size.width + 3, height: symbol.size.height + 2)
        let image = NSImage(size: size, flipped: false) { _ in
            func plus(centre: NSPoint, arm: CGFloat, thickness: CGFloat) -> NSBezierPath {
                let path = NSBezierPath()
                let t = thickness / 2
                path.append(NSBezierPath(rect: NSRect(x: centre.x - arm, y: centre.y - t, width: arm * 2, height: thickness)))
                path.append(NSBezierPath(rect: NSRect(x: centre.x - t, y: centre.y - arm, width: thickness, height: arm * 2)))
                return path
            }
            symbol.draw(in: NSRect(x: 0, y: 2, width: symbol.size.width, height: symbol.size.height))
            let centre = NSPoint(x: size.width - 3.4, y: 3.4)
            let arm: CGFloat = 2.9, thickness: CGFloat = 1.5
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: centre.x - 4.9, y: centre.y - 4.9, width: 9.8, height: 9.8)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            plus(centre: centre, arm: arm, thickness: thickness).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The editor: the code brackets.
    static func editor() -> NSImage {
        template(NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9.5, weight: .semibold)))
    }

    private static func template(_ image: NSImage?) -> NSImage {
        let image = image ?? NSImage()
        image.isTemplate = true
        return image
    }
}

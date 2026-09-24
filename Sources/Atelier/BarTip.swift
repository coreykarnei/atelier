import AppKit

/// A tooltip that opens *above* its control (2026-09-23, owner call). The
/// system's tip always drops below the pointer, and at the bottom bar that
/// is the screen's edge (or the Dock). Two voices (§1.4): the sentence in
/// SF Pro, the chord after it in mono, dimmer — "New Session Here  ⌥⌘T"
/// splits on its double space. Shown after the system's hover delay, gone
/// on exit or press; a short fade in, a plain appear under Reduce Motion.
final class BarTip {
    static let shared = BarTip()

    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")
    private var pending: DispatchWorkItem?
    private weak var anchor: NSView?

    /// The macOS tooltip delay, near enough; the first tip waits for it,
    /// and moving straight to a neighbour shows at once, as the system does.
    private static let delay: TimeInterval = 0.7
    private var lastHidden = Date.distantPast
    private static let gap: CGFloat = 6

    func schedule(_ text: String, above view: NSView) {
        cancel()
        anchor = view
        let warm = Date().timeIntervalSince(lastHidden) < 0.5
        let work = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, view.window != nil else { return }
            self.show(text, above: view)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warm ? 0 : Self.delay), execute: work)
    }

    func cancel(for view: NSView? = nil) {
        if let view, anchor !== view { return }
        pending?.cancel()
        pending = nil
        if let panel, panel.isVisible {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            lastHidden = Date()
        }
        anchor = nil
    }

    private func show(_ text: String, above view: NSView) {
        guard let window = view.window else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        label.attributedStringValue = Self.attributed(text)
        let textSize = label.fittingSize
        let size = NSSize(width: ceil(textSize.width) + 16, height: ceil(textSize.height) + 8)
        label.frame = NSRect(x: 8, y: 4, width: ceil(textSize.width), height: ceil(textSize.height))

        let rect = view.convert(view.bounds, to: nil)
        let onScreen = window.convertToScreen(rect)
        var origin = NSPoint(x: round(onScreen.midX - size.width / 2), y: onScreen.maxY + Self.gap)
        // Kept inside the window's own screen, horizontally.
        if let visible = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
            panel.orderFront(nil)
        } else {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.Elevation.surface0.cgColor
        content.layer?.cornerRadius = Theme.Elevation.radiusSmall
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Theme.Elevation.hairline.cgColor
        panel.contentView = content
        content.addSubview(label)
        return panel
    }

    private static func attributed(_ text: String) -> NSAttributedString {
        let parts = text.components(separatedBy: "  ")
        let result = NSMutableAttributedString(string: parts[0], attributes: [
            .font: Theme.Typography.ui(Theme.Typography.small),
            .foregroundColor: Theme.chromeText,
        ])
        if parts.count > 1 {
            result.append(NSAttributedString(string: "  " + parts.dropFirst().joined(separator: "  "), attributes: [
                .font: Theme.Typography.mono(Theme.Typography.small),
                .foregroundColor: Theme.chromeMutedText,
            ]))
        }
        return result
    }
}

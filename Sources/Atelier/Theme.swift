import AppKit
import SwiftTerm

/// Catppuccin Mocha — the single source of truth for color across Atelier's
/// components. Aesthetic is a spec requirement, not decoration (see VISION.md /
/// TECHNICAL_PLAN §2.9). Tokens are added here as components start using them.
enum Theme {
    /// The 16-color ANSI palette SwiftTerm installs into each terminal.
    /// Order: 0-7 normal, 8-15 bright.
    static let ansi: [SwiftTerm.Color] = [
        hexTerm(0x45475A), // 0  black   (surface1)
        hexTerm(0xF38BA8), // 1  red
        hexTerm(0xA6E3A1), // 2  green
        hexTerm(0xF9E2AF), // 3  yellow
        hexTerm(0x89B4FA), // 4  blue
        hexTerm(0xF5C2E7), // 5  magenta (pink)
        hexTerm(0x94E2D5), // 6  cyan    (teal)
        hexTerm(0xBAC2DE), // 7  white   (subtext1)
        hexTerm(0x585B70), // 8  bright black   (surface2)
        hexTerm(0xF38BA8), // 9  bright red
        hexTerm(0xA6E3A1), // 10 bright green
        hexTerm(0xF9E2AF), // 11 bright yellow
        hexTerm(0x89B4FA), // 12 bright blue
        hexTerm(0xF5C2E7), // 13 bright magenta
        hexTerm(0x94E2D5), // 14 bright cyan
        hexTerm(0xA6ADC8), // 15 bright white  (subtext0)
    ]

    static let terminalBackground = hexTerm(0x1E1E2E) // base
    static let terminalForeground = hexTerm(0xCDD6F4) // text
    static let terminalCursor = hexTerm(0xF5E0DC)     // rosewater

    // Chrome tokens (non-terminal AppKit views).
    static let editorPlaceholderBackground = nsColor(0x181825) // mantle
    static let chromeMutedText = nsColor(0x6C7086)             // overlay0
    static let chromeText = nsColor(0xCDD6F4)                  // text
    static let bottomBarBackground = nsColor(0x181825)         // mantle
    static let bottomBarBorder = nsColor(0x313244)             // surface0
    static let tabActiveBackground = nsColor(0x313244)         // surface0
    static let accentBlue = nsColor(0x89B4FA)                  // blue
    static let accentGreen = nsColor(0xA6E3A1)                 // green
    static let accentRed = nsColor(0xF38BA8)                   // red
    static let accentPeach = nsColor(0xFAB387)                 // peach
    /// Dark text on accent fills — the tmux status-bar look (blue/green pill, base text).
    static let accentTextDark = nsColor(0x1E1E2E)              // base

    /// AppKit chrome color from a 0xRRGGBB hex.
    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// SwiftTerm.Color uses 16-bit channels (0–65535).
    private static func hexTerm(_ hex: UInt32) -> SwiftTerm.Color {
        let r = UInt16((hex >> 16) & 0xFF) * 257
        let g = UInt16((hex >> 8) & 0xFF) * 257
        let b = UInt16(hex & 0xFF) * 257
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }
}

import AppKit
import SwiftTerm

/// Catppuccin Mocha — the single source of truth for color, elevation, and type
/// across Atelier's components. Aesthetic is a spec requirement, not decoration
/// (see VISION.md / TECHNICAL_PLAN §2.9); the rules these tokens encode are
/// binding (docs/POLISH_PLAN.md §1).
enum Theme {
    // MARK: §2.1 Translucency

    /// The one translucency constant (POLISH_PLAN §2.1): how opaque the *fields*
    /// are over the behind-window blur. Applies to fields, never text — glyphs
    /// stay full-contrast per §1.2. Tune against a busy desktop: the test is
    /// "depth without noise"; if wallpaper detail competes with text, raise it.
    static let fieldAlpha: CGFloat = 0.85

    /// `fieldAlpha`, collapsed to opaque when the user asks for Reduce
    /// Transparency (§1.5). Read at apply-time, not cached.
    static var effectiveFieldAlpha: CGFloat {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1.0 : fieldAlpha
    }

    // MARK: Elevation (POLISH_PLAN Phase 0)

    /// Elevation *is* the Catppuccin layer: the Mocha neutral ramp maps
    /// one-to-one onto the z-axis. Field surfaces (crust/mantle/base) carry the
    /// translucency token; raised and floating surfaces are opaque fills.
    enum Elevation {
        /// Recessed wells — empty results panel, editor placeholder field.
        static var crust: NSColor { translucent(0x11111B) }
        /// Bars and frames — the bottom bar.
        static var mantle: NSColor { translucent(0x181825) }
        /// Content — the terminals.
        static var base: NSColor { translucent(0x1E1E2E) }
        /// Raised controls — active tab, keycap chips.
        static let surface0 = nsColor(0x313244)
        /// Floating surfaces — fan, palette — over stronger blur.
        static let surface1 = nsColor(0x45475A)

        /// 1 px line between stacked chrome surfaces (bar top border, dividers).
        static let frameLine = nsColor(0x313244) // surface0

        /// The lighting model: light comes from above. Every floating surface
        /// wears a 1 px top hairline…
        static let hairline = NSColor.white.withAlphaComponent(0.06)
        /// …modals sit behind a dimmed scrim…
        static let scrim = NSColor.black.withAlphaComponent(0.35)

        /// …and there are exactly two shadows in the entire app.
        static var raisedShadow: NSShadow { shadow(y: 2, blur: 8, alpha: 0.25) }
        static var floatingShadow: NSShadow { shadow(y: 8, blur: 24, alpha: 0.35) }

        /// Corner radii — the three-value scale. Nothing else.
        static let radiusSmall: CGFloat = 4   // pills, tabs, keycaps
        static let radiusMedium: CGFloat = 6  // popover rows, small cards
        static let radiusLarge: CGFloat = 10  // floating overlays

        private static func translucent(_ hex: UInt32) -> NSColor {
            nsColor(hex).withAlphaComponent(Theme.effectiveFieldAlpha)
        }

        private static func shadow(y: CGFloat, blur: CGFloat, alpha: CGFloat) -> NSShadow {
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -y) // below: light is above
            shadow.shadowBlurRadius = blur
            shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
            return shadow
        }
    }

    // MARK: Type (POLISH_PLAN §1.4 codified)

    /// The two-voice rule: if a string could be pasted into a terminal and mean
    /// something, it is mono (paths, branches, commands, keycap contents,
    /// session titles, the clock). When Atelier itself speaks — sentence-shaped
    /// chrome — it speaks SF Pro.
    ///
    /// (The plan calls this `Theme.Type`; Swift reserves `Type` as a member
    /// name, hence `Typography`.)
    enum Typography {
        /// Three sizes. Nothing else.
        static let small: CGFloat = 11
        static let body: CGFloat = 13
        static let large: CGFloat = 15

        /// The mono voice — JetBrains Mono (the terminal's own face), falling
        /// back to the system mono if it isn't installed.
        static func mono(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            let face: String
            switch weight {
            case .bold, .heavy, .black: face = "JetBrainsMono-Bold"
            case .semibold: face = "JetBrainsMono-SemiBold"
            case .medium: face = "JetBrainsMono-Medium"
            default: face = "JetBrainsMono-Regular"
            }
            return NSFont(name: face, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
        }

        /// Atelier's own voice — SF Pro, always with tabular numerals: anything
        /// with digits must not shift its neighbors when they change.
        static func ui(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            let descriptor = base.fontDescriptor.addingAttributes([
                .featureSettings: [[
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector,
                ]],
            ])
            return NSFont(descriptor: descriptor, size: size) ?? base
        }

        /// The one keycap-chip style (applied to overlays in Phase 4).
        enum Keycap {
            static var font: NSFont { Typography.mono(Typography.small) }
            static let fill = Elevation.surface0
            static let radius = Elevation.radiusSmall
            static let topEdge = Elevation.hairline
        }
    }

    // MARK: Terminal palette

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

    // MARK: Chrome tokens (non-terminal AppKit views)

    /// §1.2 contrast discipline: terminal *content* runs at full `text`
    /// contrast; chrome never exceeds subtext0 except the attention accents.
    /// Nothing in the app is ever pure white.
    /// The M2 editor's syntax palette — Catppuccin Mocha's canonical code
    /// mapping, aligned with the ANSI palette the terminals already speak.
    /// One shared Mocha definition across editor, terminals, chrome
    /// (TECHNICAL_PLAN §2.9).
    enum Editor {
        static let text = nsColor(0xCDD6F4)        // text
        static let cursor = nsColor(0xF5E0DC)      // rosewater — same as terminals
        static let invisibles = nsColor(0x45475A)  // surface1
        static let keyword = nsColor(0xCBA6F7)     // mauve
        static let function = nsColor(0x89B4FA)    // blue
        static let type = nsColor(0xF9E2AF)        // yellow
        static let attribute = nsColor(0xFAB387)   // peach
        static let constant = nsColor(0xFAB387)    // peach
        static let number = nsColor(0xFAB387)      // peach
        static let string = nsColor(0xA6E3A1)      // green
        static let character = nsColor(0x94E2D5)   // teal
        static let command = nsColor(0x89DCEB)     // sky
        static let comment = nsColor(0x6C7086)     // overlay0
        static let selection = nsColor(0x585B70).withAlphaComponent(0.5)     // surface2
        static let lineHighlight = nsColor(0x313244).withAlphaComponent(0.5) // surface0
    }

    static let chromeText = nsColor(0xA6ADC8)      // subtext0 — the §1.2 cap
    static let chromeMutedText = nsColor(0x6C7086) // overlay0
    static let accentBlue = nsColor(0x89B4FA)      // blue
    static let accentGreen = nsColor(0xA6E3A1)     // green
    static let accentRed = nsColor(0xF38BA8)       // red
    static let accentPeach = nsColor(0xFAB387)     // peach
    /// Dark text on accent fills — the tmux status-bar look (blue/green pill, base text).
    static let accentTextDark = nsColor(0x1E1E2E)  // base

    // MARK: Focus articulation (POLISH_PLAN Phase 1)

    /// "Which pane has focus" is a literal sentence in VISION's definition of
    /// done. The focused pane wears a 1 px lavender hairline along its divider
    /// edges; a focus jump glows it briefly, then it settles and is *still*.
    enum Focus {
        static let hairline = nsColor(0xB4BEFE)   // lavender
        static let restingOpacity: Float = 0.55
        static let glowDuration: TimeInterval = 0.15
    }

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

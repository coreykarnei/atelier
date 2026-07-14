import AppKit

/// The behind-window blur, done the way the reference stack does it (§2.9;
/// the dotfiles Ghostty config is the target feel: `background-opacity 0.75`,
/// `background-blur-radius 20`).
///
/// AppKit's `NSVisualEffectView` materials are the wrong instrument here:
/// every material carries its own near-opaque tint, and stacked under the
/// fieldAlpha surfaces the window compounded to ~97% opaque — the
/// "still not semi transparent" bug wasn't a flag, it was arithmetic. The
/// WindowServer blur is tint-free: the desktop is blurred in place and the
/// fields' translucent mocha is the only wash on top, so `Theme.fieldAlpha`
/// becomes the *actual* net opacity — one honest knob.
///
/// `CGSSetWindowBackgroundBlurRadius` is private but long-stable — Ghostty
/// and Alacritty ship it. Resolved via dlsym so a future macOS that drops the
/// symbol degrades to an unblurred (still translucent) window, not a crash;
/// the caller falls back to a visual-effect material in that case.
enum WindowBackgroundBlur {
    private typealias CGSConnectionID = UInt32
    private typealias MainConnectionID = @convention(c) () -> CGSConnectionID
    private typealias SetBlurRadius = @convention(c) (CGSConnectionID, UInt32, UInt32) -> Int32

    /// dlsym's RTLD_DEFAULT.
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    @discardableResult
    static func apply(to window: NSWindow, radius: Int) -> Bool {
        guard window.windowNumber > 0,
              let setBlurSym = dlsym(rtldDefault, "CGSSetWindowBackgroundBlurRadius"),
              let connectionSym = dlsym(rtldDefault, "CGSMainConnectionID")
        else { return false }
        let mainConnection = unsafeBitCast(connectionSym, to: MainConnectionID.self)
        let setBlurRadius = unsafeBitCast(setBlurSym, to: SetBlurRadius.self)
        return setBlurRadius(mainConnection(), UInt32(window.windowNumber), UInt32(radius)) == 0
    }
}

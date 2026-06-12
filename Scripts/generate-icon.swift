#!/usr/bin/env swift
// The app icon (POLISH_PLAN §4): the triptych as the mark — three rounded
// panes in the canonical proportions (editor top-left, shell below it, agent
// right), base-on-crust, the agent pane carrying the lavender accent. Flat,
// geometric, no lighting theater.
//
// Usage: swift Scripts/generate-icon.swift
// Writes Resources/AppIcon.icns (via a temporary .iconset + iconutil).

import AppKit

let crust = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x1B / 255, alpha: 1)
let base = NSColor(srgbRed: 0x1E / 255, green: 0x1E / 255, blue: 0x2E / 255, alpha: 1)
let lavender = NSColor(srgbRed: 0xB4 / 255, green: 0xBE / 255, blue: 0xFE / 255, alpha: 1)

/// Draw the mark into an n×n pixel bitmap. All geometry is proportional to
/// the 1024 reference canvas: 100 margin, 185 canvas radius (the Big Sur
/// grid), 72 inner margin, 36 gutter, 44 pane radius, 47% left column,
/// 70% editor height.
func draw(size n: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let s = CGFloat(n) / 1024.0
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }

    // Canvas plate (y-up coordinates; the icon is vertically symmetric enough
    // that only the editor/shell order cares — editor on top).
    crust.setFill()
    NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s).fill()

    let inner: CGFloat = 72, gutter: CGFloat = 36
    let contentX: CGFloat = 100 + inner
    let contentY: CGFloat = 100 + inner
    let content: CGFloat = 824 - inner * 2 // 680
    let leftW = (content - gutter) * 0.47
    let agentW = content - gutter - leftW
    let editorH = (content - gutter) * 0.70
    let shellH = content - gutter - editorH
    let paneRadius = 44 * s

    base.setFill()
    // Shell (bottom-left in screen terms = lower y here).
    NSBezierPath(roundedRect: r(contentX, contentY, leftW, shellH), xRadius: paneRadius, yRadius: paneRadius).fill()
    // Editor (top-left).
    NSBezierPath(roundedRect: r(contentX, contentY + shellH + gutter, leftW, editorH), xRadius: paneRadius, yRadius: paneRadius).fill()
    // Agent (right) — the lavender accent.
    lavender.setFill()
    NSBezierPath(roundedRect: r(contentX + leftW + gutter, contentY, agentW, content), xRadius: paneRadius, yRadius: paneRadius).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    let rep = draw(size: pixels)
    try rep.representation(using: .png, properties: [:])!
        .write(to: iconset.appendingPathComponent("\(name).png"))
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("wrote \(out.path)")

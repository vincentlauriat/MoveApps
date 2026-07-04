#!/usr/bin/env swift
// Generates the MoveApps app icon set: a blue-gradient rounded square with two
// opposing horizontal arrows (bidirectional transfer — echoing the menu-bar glyph
// `arrow.left.arrow.right.circle`). Renders every macOS size at EXACT pixel
// dimensions (NSImage.lockFocus would double them on Retina) and writes them into
// Sources/MoveApps/Resources/Assets.xcassets/AppIcon.appiconset.
//
// Usage: ./Scripts/make-app-icon.swift
import AppKit

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let iconset = repoRoot.appendingPathComponent(
    "Sources/MoveApps/Resources/Assets.xcassets/AppIcon.appiconset")

guard FileManager.default.fileExists(atPath: iconset.path) else {
    FileHandle.standardError.write(Data("✗ appiconset not found: \(iconset.path)\n".utf8))
    exit(1)
}

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS Big Sur+ icon grid: the rounded square sits inside the canvas with a
    // transparent margin (~10%) so it lines up with other Dock icons. Draw everything
    // in this inset "content" box `c`; `p(fx, fy)` maps 0…1 fractions of it to canvas points.
    let m = s * 0.098
    let cs = s - 2 * m
    func p(_ fx: CGFloat, _ fy: CGFloat) -> NSPoint { NSPoint(x: m + cs * fx, y: m + cs * fy) }

    let bg = NSBezierPath(roundedRect: NSRect(x: m, y: m, width: cs, height: cs),
                          xRadius: cs * 0.2237, yRadius: cs * 0.2237)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.33, green: 0.62, blue: 1.00, alpha: 1),   // top-left, lighter
        NSColor(calibratedRed: 0.10, green: 0.34, blue: 0.86, alpha: 1),   // bottom-right, deeper
    ])!
    gradient.draw(in: bg, angle: -45)

    // Two opposing horizontal arrows (top → right, bottom → left) = bidirectional move.
    let lw = cs * 0.072
    NSColor.white.withAlphaComponent(0.97).setStroke()
    NSColor.white.withAlphaComponent(0.97).setFill()

    let xL: CGFloat = 0.255, xR: CGFloat = 0.745
    let head: CGFloat = 0.115
    let gap: CGFloat = 0.115                // vertical half-gap between the two shafts

    func arrow(fy: CGFloat, pointingRight: Bool) {
        let tip = pointingRight ? xR : xL
        let tail = pointingRight ? xL : xR
        // Shaft stops short of the tip so the head doesn't overshoot the rounded cap.
        let shaftEnd = pointingRight ? (xR - head * 0.75) : (xL + head * 0.75)
        let shaft = NSBezierPath()
        shaft.lineWidth = lw
        shaft.lineCapStyle = .round
        shaft.move(to: p(tail, fy))
        shaft.line(to: p(shaftEnd, fy))
        shaft.stroke()

        // Solid triangular head.
        let dir: CGFloat = pointingRight ? 1 : -1
        let h = NSBezierPath()
        h.move(to: p(tip, fy))
        h.line(to: p(tip - dir * head, fy + head * 0.72))
        h.line(to: p(tip - dir * head, fy - head * 0.72))
        h.close()
        h.fill()
    }

    arrow(fy: 0.5 + gap, pointingRight: true)    // upper arrow → right
    arrow(fy: 0.5 - gap, pointingRight: false)   // lower arrow → left

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let url = iconset.appendingPathComponent("icon_\(size).png")
    try! render(size).write(to: url)
    print("wrote \(url.lastPathComponent)")
}
print("✅ MoveApps app icon generated")

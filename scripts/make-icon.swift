#!/usr/bin/env swift
import AppKit
import Foundation

// Draws Kvill's app icon: the app's own signature, a dimmed syntax marker
// hanging to the left of a clean column of text. Rendered natively at every
// size rather than downscaled, so the small variants stay crisp.

let outputDirectory = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "./Kvill.iconset"

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func color(_ hex: String) -> NSColor {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16)!
    return NSColor(
        srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
        green: CGFloat((v >> 8) & 0xFF) / 255,
        blue: CGFloat(v & 0xFF) / 255,
        alpha: 1)
}

func drawIcon(size: CGFloat, in context: CGContext) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    // macOS icons sit inset inside their canvas with a squircle mask.
    let inset = size * 0.086
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = body.width * 0.2237
    let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    context.saveGState()
    shape.addClip()

    let gradient = NSGradient(
        colors: [color("#2A2D34"), color("#16171B")],
        atLocations: [0, 1],
        colorSpace: .sRGB)!
    gradient.draw(in: body, angle: -90)

    // The hanging marker, right-aligned against the text column.
    let columnX = body.minX + body.width * 0.46
    let markerFont = NSFont.monospacedSystemFont(ofSize: body.height * 0.40, weight: .medium)
    let marker = NSAttributedString(
        string: "#",
        attributes: [.font: markerFont, .foregroundColor: color("#D08A5D")])
    let markerSize = marker.size()
    marker.draw(at: NSPoint(
        x: columnX - markerSize.width - body.width * 0.055,
        y: body.midY - markerSize.height * 0.46))

    // The text column: one bright heading bar and two quieter body bars.
    let barWidth = body.width * 0.30
    let bars: [(y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor, alpha: CGFloat)] = [
        (0.585, barWidth, 0.070, color("#F2EEE8"), 1.0),
        (0.455, barWidth * 0.86, 0.045, color("#F2EEE8"), 0.5),
        (0.355, barWidth * 0.62, 0.045, color("#F2EEE8"), 0.5),
    ]
    for bar in bars {
        bar.color.withAlphaComponent(bar.alpha).setFill()
        let height = body.height * bar.height
        let barRect = NSRect(
            x: columnX, y: body.minY + body.height * bar.y,
            width: bar.width, height: height)
        NSBezierPath(roundedRect: barRect, xRadius: height / 2, yRadius: height / 2).fill()
    }

    context.restoreGState()

    // A hairline highlight along the top edge, the way macOS icons catch light.
    color("#FFFFFF").withAlphaComponent(0.10).setStroke()
    let rim = NSBezierPath(
        roundedRect: body.insetBy(dx: size * 0.004, dy: size * 0.004),
        xRadius: radius, yRadius: radius)
    rim.lineWidth = max(1, size * 0.006)
    rim.stroke()

    NSGraphicsContext.restoreGraphicsState()
}

try? FileManager.default.createDirectory(
    atPath: outputDirectory, withIntermediateDirectories: true)

for entry in sizes {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: entry.pixels, pixelsHigh: entry.pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    guard let context = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { continue }
    drawIcon(size: CGFloat(entry.pixels), in: context)

    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(entry.name).png")
    try? data.write(to: url)
}

print("Wrote \(sizes.count) images to \(outputDirectory)")

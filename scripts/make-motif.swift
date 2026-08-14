import AppKit

// Draws Kvill's signature as an abstract: syntax markers hanging in the left
// margin, dimmed and right-aligned, against a clean column of text.
//
//   swift scripts/make-motif.swift out.png WxH
//
// It is quiet on purpose. A logo is laid over the middle of this image on the
// portfolio, so anything loud in the centre would fight it.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-motif.swift out.png WxH\n".utf8))
    exit(2)
}
let output = arguments[1]
let dimensions = arguments[2].split(separator: "x").compactMap { Double($0) }
guard dimensions.count == 2 else { exit(2) }
let size = NSSize(width: dimensions[0], height: dimensions[1])

func colour(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1)
}

let ground = colour("#FAF8F3")
let ink = colour("#221F1B")
let accent = colour("#B4653A")

let scale: CGFloat = 2
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
ground.setFill()
NSRect(origin: .zero, size: size).fill()

// The column of text, and the gutter to the left of it. Every line starts on
// the same x: that is the whole idea, so the column edge is dead straight.
let columnX = (size.width * 0.30).rounded()
let columnWidth = size.width * 0.52
let gap = size.width * 0.018

/// One line: its marker, how wide the text runs, and how tall the line is.
struct Line {
    let marker: String
    let width: CGFloat
    let weight: CGFloat
    let leading: CGFloat
}

let lines: [Line] = [
    Line(marker: "#", width: 0.72, weight: 1.6, leading: 1.9),
    Line(marker: "", width: 0.98, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.91, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.46, weight: 1.0, leading: 1.7),
    Line(marker: "##", width: 0.54, weight: 1.35, leading: 1.8),
    Line(marker: "", width: 0.95, weight: 1.0, leading: 1.0),
    Line(marker: ">", width: 0.83, weight: 1.0, leading: 1.0),
    Line(marker: ">", width: 0.61, weight: 1.0, leading: 1.7),
    Line(marker: "-", width: 0.77, weight: 1.0, leading: 1.0),
    Line(marker: "-", width: 0.88, weight: 1.0, leading: 1.0),
    Line(marker: "-", width: 0.52, weight: 1.0, leading: 1.0),
]

// The block is measured before it is drawn, so it sits centred whatever the
// canvas shape, rather than starting at a guessed offset and running out.
let unit = size.height / 17
let barHeight = unit * 0.30
let blockHeight = unit * lines.dropLast().reduce(0) { $0 + $1.leading }
var y = size.height / 2 + blockHeight / 2

let markerFont = NSFont.monospacedSystemFont(ofSize: unit * 0.46, weight: .medium)

for line in lines {
    let height = barHeight * line.weight
    ink.withAlphaComponent(line.weight > 1.1 ? 0.16 : 0.10).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: columnX, y: y, width: columnWidth * line.width, height: height),
        xRadius: height / 2, yRadius: height / 2
    ).fill()

    // The marker is right-aligned against the column, which is what makes a
    // first-level and a sixth-level heading finish on the same edge.
    if !line.marker.isEmpty {
        let text = NSAttributedString(string: line.marker, attributes: [
            .font: markerFont, .foregroundColor: accent.withAlphaComponent(0.42),
        ])
        let measured = text.size()
        text.draw(at: NSPoint(
            x: columnX - gap - measured.width,
            y: y + height / 2 - measured.height * 0.5))
    }

    y -= unit * line.leading
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: output))
print("drew \(output)  \(Int(size.width * scale))x\(Int(size.height * scale))")

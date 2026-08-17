import AppKit

// Draws Kvill's signature as an abstract: syntax markers hanging in the left
// margin, dimmed and right-aligned, against a clean column of text.
//
//   swift scripts/make-motif.swift out.png WxH [--band F] [--logo-band F]
//
// It is quiet on purpose. A logo is laid over the middle of this image on the
// portfolio, so anything loud in the centre would fight it.
//
// --band is the fraction of the width that survives where the image is used.
// The portfolio tile is 300x458 and fills itself with `background-size: cover`
// from a 1448x984 image, which keeps the middle 44.5% of the width and throws
// the rest away. The first version of this drawing was laid out across the full
// canvas, so every marker sat in the part that gets discarded and the tile was
// bars and nothing else. Everything that has to be seen is composed inside the
// band; the bars deliberately run out past its right edge, so the crop reads as
// a page that continues rather than one that stops.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data(
        "usage: make-motif.swift out.png WxH [--band F] [--logo-band F]\n".utf8))
    exit(2)
}
let output = arguments[1]
let dimensions = arguments[2].split(separator: "x").compactMap { Double($0) }
guard dimensions.count == 2 else { exit(2) }
let size = NSSize(width: dimensions[0], height: dimensions[1])

func option(_ name: String, _ fallback: CGFloat) -> CGFloat {
    guard let at = arguments.firstIndex(of: name), arguments.count > at + 1,
          let value = Double(arguments[at + 1]) else { return fallback }
    return CGFloat(value)
}

/// How much of the width is still on screen where this is used.
let band = option("--band", 1.0)
/// How much of the height the logo covers, centred. Bars are thinned there.
let logoBand = option("--logo-band", 0.16)

func colour(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1)
}

let groundTop = colour("#FBF8F2")
let groundBottom = colour("#EFE7D8")
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

// Paper, warmed towards the bottom. Flat cream read as an unloaded image next
// to the photographs the other tiles use.
NSGradient(starting: groundTop, ending: groundBottom)?
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)

// --- Where the column sits --------------------------------------------------
// Everything is measured off the visible band, not off the canvas.
let bandX = size.width * (1 - band) / 2
let bandWidth = size.width * band
let gutter = bandWidth * 0.24
let columnX = (bandX + gutter).rounded()
// Wider than the band on purpose, so long lines leave the frame.
let measure = bandWidth * 1.5
let gap = bandWidth * 0.05

/// One line: its marker, how far the text runs, how heavy it is, and how much
/// room comes after it.
struct Line {
    let marker: String
    let width: CGFloat
    let weight: CGFloat
    let leading: CGFloat
}

// A page with a shape to it: a title, a paragraph, a section, a quote, a list.
// More lines than fit, so the block bleeds off the top and the bottom.
let lines: [Line] = [
    Line(marker: "", width: 0.88, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.52, weight: 1.0, leading: 1.8),
    Line(marker: "#", width: 0.74, weight: 1.7, leading: 1.9),
    Line(marker: "", width: 0.97, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.90, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.44, weight: 1.0, leading: 1.8),
    Line(marker: "##", width: 0.56, weight: 1.4, leading: 1.9),
    Line(marker: "", width: 0.94, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.79, weight: 1.0, leading: 1.8),
    Line(marker: ">", width: 0.86, weight: 1.0, leading: 1.0),
    Line(marker: ">", width: 0.63, weight: 1.0, leading: 1.8),
    Line(marker: "-", width: 0.81, weight: 1.0, leading: 1.0),
    Line(marker: "-", width: 0.92, weight: 1.0, leading: 1.0),
    Line(marker: "-", width: 0.55, weight: 1.0, leading: 1.8),
    Line(marker: "###", width: 0.48, weight: 1.25, leading: 1.9),
    Line(marker: "", width: 0.95, weight: 1.0, leading: 1.0),
    Line(marker: "", width: 0.71, weight: 1.0, leading: 1.0),
]

let unit = size.height / 15
let barHeight = unit * 0.30
let markerFont = NSFont.monospacedSystemFont(ofSize: unit * 0.44, weight: .medium)

// Measured before it is drawn, so it sits centred whatever the canvas shape.
let blockHeight = unit * lines.dropLast().reduce(0) { $0 + $1.leading }
var y = size.height / 2 + blockHeight / 2

// The logo lands here. Nothing gets to be dark behind a wordmark.
let logoTop = size.height * (0.5 + logoBand / 2)
let logoBottom = size.height * (0.5 - logoBand / 2)

for line in lines {
    let height = barHeight * line.weight
    let heading = line.weight > 1.1
    let middle = y + height / 2

    // Fade at the edges, so the page runs off rather than stopping dead, and
    // again behind the logo.
    let edgeFade = min(1, min(middle, size.height - middle) / (size.height * 0.13))
    let logoFade = (middle < logoTop && middle > logoBottom) ? 0.35 : 1.0
    let strength = edgeFade * logoFade

    ink.withAlphaComponent((heading ? 0.24 : 0.135) * strength).setFill()
    NSBezierPath(
        roundedRect: NSRect(x: columnX, y: y, width: measure * line.width, height: height),
        xRadius: height / 2, yRadius: height / 2
    ).fill()

    // The marker is right-aligned against the column, which is what makes a
    // first-level and a sixth-level heading finish on the same edge.
    if !line.marker.isEmpty, logoFade == 1.0 {
        let text = NSAttributedString(string: line.marker, attributes: [
            .font: markerFont, .foregroundColor: accent.withAlphaComponent(0.66 * edgeFade),
        ])
        let measured = text.size()
        text.draw(at: NSPoint(
            x: columnX - gap - measured.width,
            y: middle - measured.height * 0.5))
    }

    y -= unit * line.leading
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: output))
print("drew \(output)  \(Int(size.width * scale))x\(Int(size.height * scale))"
    + "  band \(band), visible x \(Int(bandX * scale))-\(Int((bandX + bandWidth) * scale))")

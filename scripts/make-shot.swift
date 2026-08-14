import AppKit

// Composes an App Store screenshot: a headline, and the rendered page inside a
// window that looks like a window.
//
//   swift scripts/make-shot.swift out.png page.png "Headline" "Sub line" light
//
// The page image is whatever `--render` produced. Everything else is drawn here,
// because the real window's chrome is glass and glass renders as nothing when it
// is not on a screen.

let arguments = CommandLine.arguments
guard arguments.count >= 6 else {
    FileHandle.standardError.write(Data("usage: make-shot.swift out.png page.png headline subline light|dark\n".utf8))
    exit(2)
}
let output = arguments[1]
let pagePath = arguments[2]
let headline = arguments[3]
let subline = arguments[4]
let dark = arguments[5] == "dark"

// Apple takes 2880x1800 for macOS. Everything below is in points at half that.
let scale: CGFloat = 2
let size = NSSize(width: 1440, height: 900)

func colour(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1)
}

let ink = dark ? colour("#F2EFE9") : colour("#221F1B")
let quiet = dark ? colour("#9A948A") : colour("#77706A")
let top = dark ? colour("#15171A") : colour("#F3EFE7")
let bottom = dark ? colour("#0C0D0F") : colour("#E7E0D3")

guard let page = NSImage(contentsOfFile: pagePath) else {
    FileHandle.standardError.write(Data("cannot read \(pagePath)\n".utf8))
    exit(1)
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// --- Ground ---------------------------------------------------------------
NSGradient(starting: top, ending: bottom)?
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)

// --- Words ----------------------------------------------------------------
// The same system families the app itself resolves, so the words around the
// window are set in the typeface the window is showing off.
func font(_ design: NSFontDescriptor.SystemDesign, _ points: CGFloat,
          _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: points, weight: weight)
    guard let designed = base.fontDescriptor.withDesign(design) else { return base }
    return NSFont(descriptor: designed, size: points) ?? base
}

let title = NSMutableParagraphStyle()
title.alignment = .center
let headlineFont = font(.serif, 48, .semibold)
(headline as NSString).draw(
    in: NSRect(x: 100, y: 762, width: size.width - 200, height: 60),
    withAttributes: [.font: headlineFont, .foregroundColor: ink, .paragraphStyle: title])
(subline as NSString).draw(
    in: NSRect(x: 200, y: 726, width: size.width - 400, height: 30),
    withAttributes: [
        .font: font(.default, 19, .regular),
        .foregroundColor: quiet, .paragraphStyle: title,
    ])

// --- The window -----------------------------------------------------------
let card = NSRect(x: 220, y: 66, width: size.width - 440, height: 630)
let radius: CGFloat = 14
let bar: CGFloat = 34

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -18), blur: 46,
        color: NSColor.black.withAlphaComponent(dark ? 0.55 : 0.2).cgColor)
    (dark ? colour("#191B1F") : NSColor.white).setFill()
    NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius).fill()
    context.restoreGState()
}

// The page, clipped to the window below its title bar.
let inner = NSRect(x: card.minX, y: card.minY,
                   width: card.width, height: card.height - bar)
NSGraphicsContext.saveGraphicsState()
NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius).addClip()
page.draw(in: inner, from: .zero, operation: .sourceOver, fraction: 1,
          respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
NSGraphicsContext.restoreGraphicsState()

// Traffic lights, and a hairline under the bar.
let lights = [colour("#FF5F57"), colour("#FEBC2E"), colour("#28C840")]
for (index, light) in lights.enumerated() {
    light.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: card.minX + 20 + CGFloat(index) * 20,
        y: card.maxY - bar / 2 - 6, width: 12, height: 12)).fill()
}
(dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.07)).setFill()
NSRect(x: card.minX, y: card.maxY - bar, width: card.width, height: 1).fill()

// A hairline around the whole window, so it reads as an object on the page.
(dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.09)).setStroke()
let edge = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5),
                        xRadius: radius, yRadius: radius)
edge.lineWidth = 1
edge.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: output))
print("composed \(output)")

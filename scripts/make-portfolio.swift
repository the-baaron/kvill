import AppKit

// Composes an image of Kvill for a case study: a rendered page inside a window,
// on the ground the app's own palette uses.
//
//   swift scripts/make-portfolio.swift out.png WxH light|dark page.png [sidebar.png]
//
//     --wash HEX A            flat colour over everything, A from 0 to 1
//     --fade HEX A0 A1 HOLD [END]
//                             the same colour vertically, A0 down to A1, held
//                             at A0 for the top HOLD of the height and reaching
//                             A1 at END. END defaults to 0.92
//     --drop F                how far the window hangs off the bottom, as a
//                             fraction of the height. Default 0.12
//
// The page comes from the app itself, so what is shown is what the app draws.
// The window around it is composed here for the same reason the App Store shots
// are: the real chrome is glass, and glass renders as nothing off screen.
//
// --fade exists because a header on the portfolio has the project title and the
// intro paragraph set over it. A flat --wash strong enough to keep that text
// readable flattens the whole picture with it, and the first Kvill header went
// out that way: the window was a ghost and the traffic lights sat behind the
// intro. The other case studies fade top to bottom instead, so the words sit on
// clean ground and the image is at full strength below them.

let arguments = CommandLine.arguments
guard arguments.count >= 5 else {
    FileHandle.standardError.write(Data(
        "usage: make-portfolio.swift out.png WxH light|dark page.png [sidebar.png]\n".utf8))
    exit(2)
}
let output = arguments[1]
let dimensions = arguments[2].split(separator: "x").compactMap { Double($0) }
guard dimensions.count == 2 else { exit(2) }
let size = NSSize(width: dimensions[0], height: dimensions[1])
let dark = arguments[3] == "dark"
let pagePath = arguments[4]
// The sidebar is optional and the flags come after it, so a leading dash means
// there is no sidebar rather than a file called "--wash".
let sidebarPath = arguments.count > 5 && !arguments[5].hasPrefix("--") ? arguments[5] : nil

func colour(_ hex: String) -> NSColor {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    return NSColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1)
}

let top = dark ? colour("#16181C") : colour("#F5F1E9")
let bottom = dark ? colour("#0B0C0E") : colour("#E6DFD1")

guard let page = NSImage(contentsOfFile: pagePath) else {
    FileHandle.standardError.write(Data("cannot read \(pagePath)\n".utf8))
    exit(1)
}
let sidebar = sidebarPath.flatMap { NSImage(contentsOfFile: $0) }
if sidebarPath != nil, sidebar == nil {
    FileHandle.standardError.write(Data("cannot read \(sidebarPath!)\n".utf8))
    exit(1)
}

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

NSGradient(starting: top, ending: bottom)?
    .draw(in: NSRect(origin: .zero, size: size), angle: -90)

// The window runs off the bottom edge: a page that continues past the frame
// reads as a document, where a neatly centred rectangle reads as a picture.
let drop: CGFloat = {
    guard let at = arguments.firstIndex(of: "--drop"), arguments.count > at + 1,
          let value = Double(arguments[at + 1]) else { return 0.12 }
    return CGFloat(value)
}()
let margin = (size.width * 0.115).rounded()
let card = NSRect(
    x: margin, y: -(size.height * drop).rounded(),
    width: size.width - margin * 2, height: size.height)
let radius: CGFloat = 16
let frame = NSBezierPath(roundedRect: card, xRadius: radius, yRadius: radius)

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -22), blur: 54,
        color: NSColor.black.withAlphaComponent(dark ? 0.6 : 0.22).cgColor)
    (dark ? colour("#17191D") : NSColor.white).setFill()
    frame.fill()
    context.restoreGState()
}

let sidebarWidth = sidebar == nil ? 0 : (card.width * 0.22).rounded()

// The page is drawn at its own aspect or not at all. Rendering at one shape and
// drawing into another squashes the type, which is the sort of thing that
// survives a glance and ruins a case study.
let pageBox = NSSize(width: card.width - sidebarWidth, height: card.height)
let drawn = page.size
if abs(drawn.width / drawn.height - pageBox.width / pageBox.height) > 0.01 {
    let wanted = "\(Int(pageBox.width))x\(Int(pageBox.height))"
    let complaint = "page is \(Int(drawn.width))x\(Int(drawn.height)), "
        + "window needs \(wanted). Re-render at --geometry \(wanted).\n"
    FileHandle.standardError.write(Data(complaint.utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
frame.addClip()
if let sidebar {
    sidebar.draw(
        in: NSRect(x: card.minX, y: card.minY, width: sidebarWidth, height: card.height),
        from: .zero, operation: .sourceOver, fraction: 1,
        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
}
page.draw(
    in: NSRect(x: card.minX + sidebarWidth, y: card.minY,
               width: card.width - sidebarWidth, height: card.height),
    from: .zero, operation: .sourceOver, fraction: 1,
    respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
NSGraphicsContext.restoreGraphicsState()

// Traffic lights sit in the margin the page already leaves. There is no title
// bar to draw: the app does not have one.
for (index, light) in [colour("#FF5F57"), colour("#FEBC2E"), colour("#28C840")].enumerated() {
    light.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: card.minX + 22 + CGFloat(index) * 20,
        y: card.maxY - 27, width: 12, height: 12)).fill()
}

(dark ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.08)).setStroke()
let edge = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5),
                        xRadius: radius, yRadius: radius)
edge.lineWidth = 1
edge.stroke()

// A wash, for an image that has to sit behind text. The portfolio uses its
// header as a section background with the title set over it, so the image is
// faded almost into the page colour rather than competing with it.
if let at = arguments.firstIndex(of: "--wash"), arguments.count > at + 2,
   let strength = Double(arguments[at + 2]) {
    colour(arguments[at + 1]).withAlphaComponent(CGFloat(strength)).setFill()
    NSRect(origin: .zero, size: size).fill()
}

// The same thing graded down the height: solid where the words are, thinning
// to almost nothing below them.
if let at = arguments.firstIndex(of: "--fade"), arguments.count > at + 4,
   let topAlpha = Double(arguments[at + 2]),
   let bottomAlpha = Double(arguments[at + 3]),
   let hold = Double(arguments[at + 4]) {
    let veil = colour(arguments[at + 1])
    let end = arguments.count > at + 5 ? (Double(arguments[at + 5]) ?? 0.92) : 0.92
    // Locations run along the drawing direction, and -90 draws downwards, so 0
    // is the top of the canvas.
    NSGradient(colorsAndLocations:
        (veil.withAlphaComponent(CGFloat(topAlpha)), 0),
        (veil.withAlphaComponent(CGFloat(topAlpha)), CGFloat(hold)),
        (veil.withAlphaComponent(CGFloat(bottomAlpha)), CGFloat(end)),
        (veil.withAlphaComponent(CGFloat(bottomAlpha)), 1))?
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: output))
print("composed \(output)  \(Int(size.width * scale))x\(Int(size.height * scale))")

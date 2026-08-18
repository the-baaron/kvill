import AppKit

// Composes an App Store screenshot: some words, and the rendered page inside a
// window drawn to look like the real one.
//
//   swift scripts/make-shot.swift out.png page.png layout light|dark "Headline" "Sub line" [sidebar.png]
//
//   layout: centre | right | left
//     centre  window in the middle, words above it
//     right   window running off the right edge, words down the left
//     left    window running off the left edge, words down the right
//
// Kvill's window has no title bar: the content view is full size and the bar is
// transparent, so the page runs right up under the traffic lights. Drawing a
// grey strip across the top, which is what a generic mockup does, would show
// something the app does not have. The page fills the whole window here and the
// lights sit on top of it, in the margin the page already leaves.

let arguments = CommandLine.arguments
guard arguments.count >= 7 else {
    FileHandle.standardError.write(Data(
        "usage: make-shot.swift out.png page.png centre|right|left light|dark headline subline\n".utf8))
    exit(2)
}
let output = arguments[1]
let pagePath = arguments[2]
let layout = arguments[3]
let dark = arguments[4] == "dark"
// Which palette the page was rendered in, so the ground can be tinted to match.
let theme = ProcessInfo.processInfo.environment["SHOT_THEME"] ?? ""

/// A photograph of the real window, if this shot has one.
///
/// Drawing a window is fine for a page and falls apart for anything else. The
/// sidebar had to be rendered apart and composed back, which put a seam where
/// the app has none and cut the top off it, and glass chrome does not render
/// off screen at all, so no drawn window could ever show the options panel or
/// the insert menu. Where a photograph exists it is used as it is: rounded
/// corners, real chrome, real selection, nothing reconstructed.
let photograph = ProcessInfo.processInfo.environment["SHOT_WINDOW"]
    .flatMap { NSImage(contentsOfFile: $0) }
let headline = arguments[5]
let subline = arguments[6]
// A folder open down the side of the window. Rendered separately by --tree,
// because the sidebar is a view and the page is a document, and the app has no
// one command that draws both.
let sidebarPath = arguments.count > 7 ? arguments[7] : nil

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

/// The palette's accent, taken from the app's own table. The ground is tinted
/// with it so the canvas belongs to the page sitting on it rather than being a
/// neutral slab that any editor could have been dropped onto.
let accents = [
    "paper": "#A65D3A", "ink": "#D08A5D", "sepia": "#9A5B2E",
    "nord": "#88C0D0", "contrast-light": "#0B4FCB", "contrast-dark": "#7AA2F7",
]
let accent = colour(accents[theme] ?? (dark ? "#D08A5D" : "#A65D3A"))

let ink = dark ? colour("#F4F1EB") : colour("#221F1B")
let quiet = dark ? colour("#9C958A") : colour("#756E66")
let top = dark ? colour("#16181C") : colour("#F5F1E9")
let bottom = dark ? colour("#0B0C0E") : colour("#E6DFD1")

guard let page = NSImage(contentsOfFile: pagePath) else {
    FileHandle.standardError.write(Data("cannot read \(pagePath)\n".utf8))
    exit(1)
}
// A missing sidebar is a broken shot, not a shot without a sidebar: the point
// of the picture would be gone and nothing would say so.
var sidebar: NSImage?
if let sidebarPath {
    guard let image = NSImage(contentsOfFile: sidebarPath) else {
        FileHandle.standardError.write(Data("cannot read \(sidebarPath)\n".utf8))
        exit(1)
    }
    sidebar = image
}
/// How wide the sidebar sits in the window, matching the app's own default.
let sidebarWidth: CGFloat = 232

/// Where the window sits, and where the words sit, for each layout. The window
/// is allowed to run off the canvas: a page half out of frame reads as a page
/// that continues, which a neatly centred rectangle does not.
struct Plan {
    let card: NSRect
    let text: NSRect
    let centred: Bool
}

let plan: Plan
switch layout {
case "right":
    plan = Plan(
        card: NSRect(x: 545, y: 96, width: 1010, height: 708),
        text: NSRect(x: 96, y: 360, width: 400, height: 220),
        centred: false)
case "left":
    plan = Plan(
        card: NSRect(x: -115, y: 96, width: 1010, height: 708),
        text: NSRect(x: 944, y: 360, width: 400, height: 220),
        centred: false)
case "small":
    // A whole window, on the canvas, at a size someone would actually keep on
    // half a screen. The others run off an edge to say the page continues; this
    // one says the opposite, that the app is comfortable small.
    plan = Plan(
        card: NSRect(x: 108, y: 150, width: 620, height: 600),
        text: NSRect(x: 830, y: 380, width: 430, height: 220),
        centred: false)
default:
    // The words sit lower than they used to, to leave a band at the top for the
    // mark. Without it the mark had nowhere to go on this layout: the window
    // owns both bottom corners and the headline owned the top.
    plan = Plan(
        card: NSRect(x: 215, y: 40, width: 1010, height: 640),
        text: NSRect(x: 120, y: 690, width: size.width - 240, height: 120),
        centred: true)
}

// A window with a sidebar in it is showing two things, so it keeps more of
// itself on the canvas. The usual deep bleed would cut the page's text down the
// middle of a sentence, which reads as a mistake rather than as a page that
// carries on.
var card = plan.card
if sidebar != nil {
    card.size.width = min(card.width, size.width - card.minX)
}
// A photograph is whatever size the window was. Scaling it would set the app's
// text at a size the app never uses, so the canvas takes the window rather than
// the window taking the canvas.
if let photograph {
    card.size = photograph.size
    card.origin.y = plan.centred ? plan.card.minY : (size.height - photograph.size.height) / 2
}
let plannedCard = card

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

// A wash of the palette's accent behind where the window will sit, so the light
// in the picture appears to come from the page. Flat gradients read as a
// template with a screenshot dropped into it, which is what these were.
if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    let glow = NSGradient(
        // Lighter on a pale ground. At the same strength as the dark themes the
        // wash turned cream into a grey-blue haze, which reads as a dirty
        // gradient rather than as light coming off the page.
        colors: [accent.withAlphaComponent(dark ? 0.26 : 0.10), accent.withAlphaComponent(0)])
    let centre = NSPoint(x: plannedCard.midX, y: plannedCard.midY + 60)
    glow?.draw(fromCenter: centre, radius: 40, toCenter: centre, radius: size.width * 0.62,
               options: [])
    context.restoreGState()
}

// --- Furniture -------------------------------------------------------------
// A poster rather than a template with a screenshot dropped into it: a dark
// shape running off one edge, a dot grid, an outsized marker and a watermark
// letter. Everything here is drawn, so it costs nothing to carry and cannot go
// out of date.
//
// Deliberately few. Rules on the shape and a line of type set on its side were
// tried and taken out again: five of these sit in a row on a store page, and a
// row of busy pictures reads as noise however good each one is on its own.

/// A grid of small dots, the way a sheet of graph paper starts.
func drawDots(at origin: NSPoint, columns: Int, rows: Int) {
    ink.withAlphaComponent(dark ? 0.13 : 0.16).setFill()
    for column in 0..<columns {
        for row in 0..<rows {
            // Fading out towards the far corner, so it reads as a texture that
            // begins at the edge rather than a rectangle of dots.
            let fade = 1 - (CGFloat(column) / CGFloat(columns) + CGFloat(row) / CGFloat(rows)) / 2.1
            guard fade > 0 else { continue }
            ink.withAlphaComponent((dark ? 0.13 : 0.16) * fade).setFill()
            NSBezierPath(ovalIn: NSRect(
                x: origin.x + CGFloat(column) * 15,
                y: origin.y - CGFloat(row) * 15, width: 2.6, height: 2.6)).fill()
        }
    }
}

/// An outsized syntax marker, the app's own glyph, used as an ornament.
func drawBigMarker(at point: NSPoint, size markerSize: CGFloat) {
    NSAttributedString(string: "#", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: markerSize, weight: .medium),
        .foregroundColor: accent.withAlphaComponent(0.9),
    ]).draw(at: point)
}

/// A letter at poster scale, set very quietly, running off the canvas.
func drawWatermark(_ letter: String, at point: NSPoint) {
    NSAttributedString(string: letter, attributes: [
        .font: font(.serif, 420, .bold),
        .foregroundColor: ink.withAlphaComponent(dark ? 0.055 : 0.045),
    ]).draw(at: point)
}

/// The dark shape running off an edge.
///
/// It had a few accent rules on it, standing in for lines of text. Together
/// with the captions set on their side the canvas had more furniture than
/// picture, so the shape stays and the decoration on it goes.
func drawSlab(centre: NSPoint, radius: CGFloat) {
    (dark ? colour("#0F1115") : colour("#232A36")).setFill()
    NSBezierPath(ovalIn: NSRect(x: centre.x - radius, y: centre.y - radius,
                                width: radius * 2, height: radius * 2)).fill()
}

// --- The mark --------------------------------------------------------------
/// The app icon and the wordmark, in a corner.
///
/// This replaced an abstract of markers hanging in a margin. It was the app's
/// own signature and it still read as a few grey lines with nothing to say, so
/// the thing that identifies the app is now the thing that identifies the app.
func drawMark(at point: NSPoint, centred: Bool = false) {
    let iconSize: CGFloat = 34
    if let icon = NSImage(contentsOfFile:
        "build/Kvill.app/Contents/Resources/Kvill.icns") {
        icon.draw(in: NSRect(x: point.x, y: point.y - 5, width: iconSize, height: iconSize),
                  from: .zero, operation: .sourceOver, fraction: dark ? 0.92 : 1,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    // Set in the app's own display face, which is what the wordmark is.
    let mark = NSAttributedString(string: "Kvill", attributes: [
        .font: font(.serif, 25, .semibold),
        .foregroundColor: ink.withAlphaComponent(dark ? 0.55 : 0.45),
        .kern: 0.3,
    ])
    mark.draw(at: NSPoint(x: point.x + iconSize + 12, y: point.y))
}

// Laid out around the window, in whatever the window is not using. Each layout
// keeps the same vocabulary so the five read as one set.
switch layout {
case "centre":
    // Window down the middle: both flanks are free.
    drawSlab(centre: NSPoint(x: -110, y: 300), radius: 290)
    drawDots(at: NSPoint(x: 18, y: size.height - 22), columns: 7, rows: 6)
    drawBigMarker(at: NSPoint(x: 40, y: 690), size: 46)
    drawWatermark(headline.prefix(1).uppercased(), at: NSPoint(x: size.width - 150, y: 210))
    drawMark(at: NSPoint(x: size.width / 2 - 55, y: size.height - 62), centred: true)
case "left", "small":
    // Window on the left, so everything else lives on the right.
    drawSlab(centre: NSPoint(x: size.width + 90, y: 720), radius: 250)
    drawDots(at: NSPoint(x: size.width - 110, y: 240), columns: 6, rows: 5)
    drawWatermark(headline.prefix(1).uppercased(), at: NSPoint(x: size.width - 300, y: 90))
    drawMark(at: NSPoint(x: size.width - 190, y: 74))
default:
    // Window on the right: the words and the furniture share the left.
    drawSlab(centre: NSPoint(x: -120, y: 810), radius: 240)
    drawDots(at: NSPoint(x: 18, y: 250), columns: 7, rows: 6)
    drawBigMarker(at: NSPoint(x: 96, y: 300), size: 46)
    drawMark(at: NSPoint(x: 96, y: 74))
}

// --- The window -----------------------------------------------------------
let radius: CGFloat = 16
let frame = NSBezierPath(roundedRect: plannedCard, xRadius: radius, yRadius: radius)

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -22), blur: 54,
        color: NSColor.black.withAlphaComponent(dark ? 0.6 : 0.22).cgColor)
    if let photograph {
        // The capture already carries the window's own rounded corners and
        // alpha, so it casts the shadow itself.
        photograph.draw(in: plannedCard, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true,
                        hints: [.interpolation: NSImageInterpolation.high])
    } else {
        (dark ? colour("#17191D") : NSColor.white).setFill()
        frame.fill()
    }
    context.restoreGState()
}

// Everything below draws a window. A photograph already is one, so none of
// it applies: no page to place, no lights to paint on, no hairline to make
// it read as an object.
if photograph == nil {
    // The page fills the window. No title bar: there isn't one in the app.
    NSGraphicsContext.saveGraphicsState()
    frame.addClip()
    if let sidebar {
        // Sidebar down the left, page beside it, and a divider between them the way
        // the split view draws one.
        let left = NSRect(x: plannedCard.minX, y: plannedCard.minY,
                          width: sidebarWidth, height: plannedCard.height)
        let right = NSRect(x: left.maxX, y: plannedCard.minY,
                           width: plannedCard.width - sidebarWidth, height: plannedCard.height)
        // Full height, the way the app runs it: the sidebar goes right up under the
        // transparent title bar and the traffic lights sit on it. Reserving a strip
        // for them and starting the tree below it cut the top off the sidebar and
        // gave the window a title bar it does not have.
        sidebar.draw(in: left, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        // Rendered at this width already, so drawn one to one.
        page.draw(in: right, from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        (dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.09)).setFill()
        NSRect(x: left.maxX - 0.5, y: left.minY, width: 1, height: left.height).fill()
    } else {
        page.draw(in: plannedCard, from: .zero, operation: .sourceOver, fraction: 1,
                  respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
    NSGraphicsContext.restoreGraphicsState()

    // Traffic lights, sitting in the margin the page already leaves at the top.
    for (index, light) in [colour("#FF5F57"), colour("#FEBC2E"), colour("#28C840")].enumerated() {
        light.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: plannedCard.minX + 22 + CGFloat(index) * 20,
            y: plannedCard.maxY - 27, width: 12, height: 12)).fill()
    }

    // A hairline, so the window reads as an object rather than a hole.
    (dark ? NSColor.white.withAlphaComponent(0.11) : NSColor.black.withAlphaComponent(0.08)).setStroke()
    let edge = NSBezierPath(roundedRect: plannedCard.insetBy(dx: 0.5, dy: 0.5),
                            xRadius: radius, yRadius: radius)
    edge.lineWidth = 1
    edge.stroke()
}

// --- Words ----------------------------------------------------------------
// The system families the app itself resolves, so the words around the window
// are set in the face the window is showing off.
func font(_ design: NSFontDescriptor.SystemDesign, _ points: CGFloat,
          _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: points, weight: weight)
    guard let designed = base.fontDescriptor.withDesign(design) else { return base }
    return NSFont(descriptor: designed, size: points) ?? base
}

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = plan.centred ? .center : .natural
paragraph.lineHeightMultiple = 1.04

let headlineFont = font(.serif, plan.centred ? 48 : 44, .semibold)
let headlineText = NSAttributedString(string: headline, attributes: [
    .font: headlineFont, .foregroundColor: ink, .paragraphStyle: paragraph,
])
let headlineHeight = headlineText.boundingRect(
    with: NSSize(width: plan.text.width, height: 400),
    options: [.usesLineFragmentOrigin]).height

let sublineParagraph = NSMutableParagraphStyle()
sublineParagraph.alignment = paragraph.alignment
sublineParagraph.lineHeightMultiple = 1.22
let sublineText = NSAttributedString(string: subline, attributes: [
    .font: font(.default, plan.centred ? 19 : 18, .regular),
    .foregroundColor: quiet, .paragraphStyle: sublineParagraph,
])
let sublineHeight = sublineText.boundingRect(
    with: NSSize(width: plan.text.width, height: 400),
    options: [.usesLineFragmentOrigin]).height

// Stacked from the top of the text box, so a two-line headline pushes the
// sub line down instead of overlapping it.
let gap: CGFloat = 14
headlineText.draw(with: NSRect(
    x: plan.text.minX, y: plan.text.maxY - headlineHeight,
    width: plan.text.width, height: headlineHeight),
    options: [.usesLineFragmentOrigin])
sublineText.draw(with: NSRect(
    x: plan.text.minX, y: plan.text.maxY - headlineHeight - gap - sublineHeight,
    width: plan.text.width, height: sublineHeight),
    options: [.usesLineFragmentOrigin])

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: output))
print("composed \(output)")

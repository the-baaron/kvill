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

/// The sidebar's background, taken from the render rather than written down, so
/// it follows whichever palette the shot was rendered in.
func sampledSidebarColour(_ image: NSImage) -> NSColor {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          // Top right, which is past the folder name and above the first row,
          // so it is the sidebar's own ground and nothing drawn on it.
          let colour = rep.colorAt(x: rep.pixelsWide - 4, y: 3)
    else { return dark ? colour("#1B1E23") : colour("#F3F0EA") }
    return colour.usingColorSpace(.deviceRGB) ?? colour
}

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
default:
    plan = Plan(
        card: NSRect(x: 215, y: 62, width: 1010, height: 640),
        text: NSRect(x: 120, y: 726, width: size.width - 240, height: 120),
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

// --- The window -----------------------------------------------------------
let radius: CGFloat = 16
let frame = NSBezierPath(roundedRect: plannedCard, xRadius: radius, yRadius: radius)

if let context = NSGraphicsContext.current?.cgContext {
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -22), blur: 54,
        color: NSColor.black.withAlphaComponent(dark ? 0.6 : 0.22).cgColor)
    (dark ? colour("#17191D") : NSColor.white).setFill()
    frame.fill()
    context.restoreGState()
}

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
    // The strip the traffic lights sit in. The app runs the sidebar full height
    // under a transparent title bar, so the lights are over the sidebar's own
    // colour rather than over the first row of the tree.
    let lightsStrip: CGFloat = 44
    sampledSidebarColour(sidebar).setFill()
    left.fill()
    let treeArea = NSRect(x: left.minX, y: left.minY,
                          width: left.width, height: left.height - lightsStrip)
    sidebar.draw(in: treeArea, from: .zero, operation: .sourceOver, fraction: 1,
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

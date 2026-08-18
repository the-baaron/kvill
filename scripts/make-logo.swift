import AppKit
import CoreText

// Writes Kvill's wordmark as an SVG of outlines.
//
//   swift scripts/make-logo.swift out.svg [ink] [accent]
//   swift scripts/make-logo.swift out.svg --lockup     the icon and the word
//
// The mark is the app's own signature: the syntax marker hanging to the left of
// the word, dimmed, exactly as a heading's `#` hangs in the editor's margin.
// Glyphs are converted to paths so the file carries no font dependency.

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make-logo.swift out.svg [ink] [accent]\n".utf8))
    exit(2)
}
let output = arguments[1]
/// The icon beside the word, rather than the word on its own.
///
/// Everything in the app icon is a rounded rectangle, a glyph and three bars,
/// so it is drawn here as paths rather than exported as a bitmap. The result
/// scales, prints, and can be dropped into a page or a slide without carrying a
/// PNG at four sizes.
let wantsLockup = arguments.contains("--lockup")
let colourArguments = arguments.dropFirst(2).filter { !$0.hasPrefix("--") }
let inkColour = colourArguments.first ?? "#221F1B"
let accentColour = colourArguments.dropFirst().first ?? "#B4653A"

/// The serif the app sets headings in, reached through the system design rather
/// than by family name: asking for "New York" by name returns the UI font.
func serif(_ points: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: points, weight: weight)
    guard let designed = base.fontDescriptor.withDesign(.serif),
          let font = NSFont(descriptor: designed, size: points) else { return base }
    return font
}

/// Every glyph in a string, as one path in text space.
func outline(_ string: String, font: NSFont) -> CGPath {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: string, attributes: [.font: font]))
    let combined = CGMutablePath()
    for run in (CTLineGetGlyphRuns(line) as? [CTRun] ?? []) {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        let runFont = unsafeBitCast(
            CFDictionaryGetValue(
                CTRunGetAttributes(run),
                unsafeBitCast(kCTFontAttributeName, to: UnsafeRawPointer.self)),
            to: CTFont.self)
        for index in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) else { continue }
            combined.addPath(
                glyph,
                transform: CGAffineTransform(
                    translationX: positions[index].x, y: positions[index].y))
        }
    }
    return combined
}

/// SVG path data for a CGPath, flipped from y-up text space into y-down SVG.
func pathData(_ path: CGPath, flipAbout height: CGFloat, offset: CGPoint) -> String {
    var out = ""
    func point(_ p: CGPoint) -> String {
        String(format: "%.2f %.2f", p.x + offset.x, height - (p.y + offset.y))
    }
    path.applyWithBlock { element in
        let points = element.pointee.points
        switch element.pointee.type {
        case .moveToPoint: out += "M\(point(points[0]))"
        case .addLineToPoint: out += "L\(point(points[0]))"
        case .addQuadCurveToPoint: out += "Q\(point(points[0])) \(point(points[1]))"
        case .addCurveToPoint:
            out += "C\(point(points[0])) \(point(points[1])) \(point(points[2]))"
        case .closeSubpath: out += "Z"
        @unknown default: break
        }
        out += " "
    }
    return out.trimmingCharacters(in: .whitespaces)
}

let wordSize: CGFloat = 100
let word = outline("Kvill", font: serif(wordSize, .semibold))
let markerFont = NSFont.monospacedSystemFont(ofSize: wordSize * 0.52, weight: .medium)
let marker = outline("#", font: markerFont)

let wordBox = word.boundingBox
let markerBox = marker.boundingBox
guard !wordBox.isEmpty, !markerBox.isEmpty else {
    FileHandle.standardError.write(Data("glyph outlines came back empty\n".utf8))
    exit(1)
}

// The marker hangs to the left of the word, its baseline shared, the way the
// editor sets it: one gap, right-aligned against the text column.
let gap = wordSize * 0.17
let markerOffset = CGPoint(x: -(markerBox.maxX + gap), y: wordSize * 0.05)

let padding = wordSize * 0.10
let minX = min(wordBox.minX, markerBox.minX + markerOffset.x) - padding
let maxX = max(wordBox.maxX, markerBox.maxX + markerOffset.x) + padding
let minY = min(wordBox.minY, markerBox.minY) - padding
let maxY = max(wordBox.maxY, markerBox.maxY) + padding
let width = maxX - minX
let height = maxY - minY

let origin = CGPoint(x: -minX, y: -minY)

/// The app icon, as paths, at a given size and position.
///
/// The same geometry `scripts/make-icon.swift` draws into the .icns: the
/// squircle inset inside its canvas, the hanging marker right-aligned against
/// the text column, and one bright bar with two quieter ones. Written twice on
/// purpose rather than shared, because that one draws pixels through AppKit and
/// this one writes path data, and neither wants the other's machinery.
func iconMarkup(x: CGFloat, y: CGFloat, side: CGFloat, flipAbout: CGFloat) -> String {
    let inset = side * 0.086
    let body = CGRect(x: x + inset, y: y + inset,
                      width: side - inset * 2, height: side - inset * 2)
    let radius = body.width * 0.2237
    let columnX = body.minX + body.width * 0.46
    let barWidth = body.width * 0.30

    /// One bar. The fraction is measured from the bottom, the way the icon is
    /// drawn in AppKit, and flipped here because SVG counts y downwards. Without
    /// the flip the bright heading bar came out underneath the two quiet ones,
    /// which is the icon upside down.
    func bar(_ fromBottom: CGFloat, _ width: CGFloat, _ height: CGFloat,
             _ opacity: String) -> String {
        let h = body.height * height
        let up = body.minY + body.height * fromBottom
        return """
          <rect x="\(num(columnX))" y="\(num(flipAbout - up - h))" \
        width="\(num(width))" height="\(num(h))" rx="\(num(h / 2))" \
        fill="#F2EEE8" fill-opacity="\(opacity)"/>
        """
    }

    // The marker is set in the same monospaced face the icon uses, outlined so
    // the file carries no font dependency, like the word beside it.
    let markerFont = NSFont.monospacedSystemFont(ofSize: body.height * 0.40, weight: .medium)
    let markerPath = outline("#", font: markerFont)
    let markerBounds = markerPath.boundingBoxOfPath
    let markerX = columnX - markerBounds.width - body.width * 0.055 - markerBounds.minX
    let markerY = body.midY - markerBounds.height * 0.46 - markerBounds.minY

    return """
      <rect x="\(num(body.minX))" y="\(num(flipAbout - body.maxY))" width="\(num(body.width))" \
    height="\(num(body.height))" rx="\(num(radius))" fill="#20232A"/>
      <path fill="#D08A5D" d="\(pathData(markerPath, flipAbout: flipAbout,
                                          offset: CGPoint(x: markerX, y: markerY)))"/>
    \(bar(0.585, barWidth, 0.070, "1"))
    \(bar(0.455, barWidth * 0.86, 0.045, "0.5"))
    \(bar(0.355, barWidth * 0.62, 0.045, "0.5"))
    """
}

func num(_ value: CGFloat) -> String { String(format: "%.2f", value) }

// The lockup sets the icon at the word's own height and stands it to the left,
// with a gap sized from the type rather than picked.
let iconSide = wantsLockup ? height * 1.15 : 0
let lockupGap = wantsLockup ? wordSize * 0.34 : 0
let totalWidth = wantsLockup ? iconSide + lockupGap + width : width
let totalHeight = wantsLockup ? max(iconSide, height) : height
let wordShift = wantsLockup ? iconSide + lockupGap : 0
let wordDrop = wantsLockup ? (totalHeight - height) / 2 : 0

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(num(totalWidth)) \(num(totalHeight))" \
fill="none">
\(wantsLockup ? iconMarkup(x: 0, y: (totalHeight - iconSide) / 2, side: iconSide, flipAbout: totalHeight) : "")
  <path fill="\(accentColour)" fill-opacity="0.55" d="\(pathData(
    marker, flipAbout: totalHeight,
    offset: CGPoint(x: origin.x + markerOffset.x + wordShift,
                    y: origin.y + markerOffset.y + wordDrop)))"/>
  <path fill="\(inkColour)" d="\(pathData(
    word, flipAbout: totalHeight,
    offset: CGPoint(x: origin.x + wordShift, y: origin.y + wordDrop)))"/>
</svg>

"""

try? svg.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
print("wrote \(output)  viewBox \(num(totalWidth)) x \(num(totalHeight))\(wantsLockup ? "  (lockup)" : "")")

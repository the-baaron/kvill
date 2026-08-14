import AppKit
import CoreText

// Writes Kvill's wordmark as an SVG of outlines.
//
//   swift scripts/make-logo.swift out.svg [ink] [accent]
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
let inkColour = arguments.count > 2 ? arguments[2] : "#221F1B"
let accentColour = arguments.count > 3 ? arguments[3] : "#B4653A"

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
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(String(format: "%.2f", width)) \
\(String(format: "%.2f", height))" fill="none">
  <path fill="\(accentColour)" fill-opacity="0.55" d="\(pathData(
    marker, flipAbout: height,
    offset: CGPoint(x: origin.x + markerOffset.x, y: origin.y + markerOffset.y)))"/>
  <path fill="\(inkColour)" d="\(pathData(word, flipAbout: height, offset: origin))"/>
</svg>

"""

try? svg.write(to: URL(fileURLWithPath: output), atomically: true, encoding: .utf8)
print("wrote \(output)  viewBox \(String(format: "%.0f x %.0f", width, height))")

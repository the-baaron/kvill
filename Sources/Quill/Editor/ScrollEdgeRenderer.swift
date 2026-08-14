import AppKit
import CoreImage

/// Draws a soft scroll edge: a blur of the content underneath that ramps up
/// toward the window edge, then a fade to the page colour.
///
/// macOS 26.1 has `NSScrollEdgeEffectStyle`, but AppKit only exposes it through
/// `NSTitlebarAccessoryViewController.preferredScrollEdgeEffectStyle`: an
/// accessory view in the title bar, which produced no effect over a window whose
/// title bar is deliberately empty, and offers nothing at all for the bottom
/// edge. So this is drawn here.
///
/// Two things went wrong in earlier versions and are worth not repeating:
///
/// - Gradients drawn by angle. An angle is measured in the current coordinate
///   system, and this draws into a flipped view, so every ramp came out upside
///   down. Everything here uses explicit start and end points.
/// - The blur was clipped with `CGContext.clip(to:mask:)`, which drew nothing at
///   all. The ramp is baked into the image's own alpha instead.
enum ScrollEdgeRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static let blurRadius: CGFloat = 18

    /// Draws the effect into `target`, taking its content from `sourceStrip` of
    /// the document. Both rects are in flipped coordinates, so `minY` is the top.
    static func draw(
        into target: NSRect,
        sourceStrip: NSRect,
        strongAtTop: Bool,
        pageColor: NSColor,
        scale: CGFloat,
        fade: Bool = true,
        render: (NSRect) -> Void
    ) {
        guard target.width > 2, target.height > 2,
              let context = NSGraphicsContext.current?.cgContext else { return }

        if let blurred = blur(strip: sourceStrip, scale: scale, strongAtTop: strongAtTop,
                              render: render) {
            blurred.draw(
                in: target, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: nil)
        }

        // The fade covers only the outer part of the strip. Running it the whole
        // way, as an earlier version did, painted page colour over precisely the
        // band where the blur is strongest, so all anyone saw was a fade.
        if fade {
            drawFade(in: target, color: pageColor, strongAtTop: strongAtTop, context: context)
        }
    }

    private static func drawFade(
        in rect: NSRect, color: NSColor, strongAtTop: Bool, context: CGContext
    ) {
        guard let opaque = color.usingColorSpace(.sRGB) else { return }
        let clear = opaque.withAlphaComponent(0)
        let colors = strongAtTop
            ? [opaque.cgColor, clear.cgColor]
            : [clear.cgColor, opaque.cgColor]

        // A light touch: the blur does the work, and this only stops the very
        // last few points of text from running into the window edge.
        let stops: [CGFloat] = strongAtTop ? [0, 0.3] : [0.7, 1]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: stops
        ) else { return }

        context.saveGState()
        context.clip(to: rect)
        // minY is the top of the view: these coordinates are flipped.
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: [])
        context.restoreGState()
    }

    // MARK: - Blur

    /// The strip with a progressive blur: the radius itself ramps from nothing
    /// at the inner edge to full strength at the window edge.
    ///
    /// The obvious approach, and the one this replaced, is to blur the whole
    /// strip at a fixed radius and ramp that layer's opacity over the original.
    /// It looks wrong, and it is worth knowing why: cross-fading sharp text with
    /// blurred text shows both at once through the middle of the ramp, so the
    /// text appears doubled rather than softened. `CIMaskedVariableBlur` varies
    /// the radius per pixel instead, which is a real gradual blur and never
    /// shows two copies of anything.
    private static func blur(
        strip: NSRect, scale: CGFloat, strongAtTop: Bool, render: (NSRect) -> Void
    ) -> NSImage? {
        guard let representation = renderStrip(strip: strip, scale: scale, render: render),
              let source = CIImage(bitmapImageRep: representation) else { return nil }
        let extent = source.extent

        // Core Image is bottom-up, so the top of the picture is at maxY. White
        // in the mask means full radius, black means untouched.
        let strongEdge = strongAtTop ? extent.maxY : extent.minY
        // The ramp spans the outer half of the strip. Running it further in left
        // text softened well away from the edge, which reads as a smeared page
        // rather than an edge treatment.
        let weakEdge = strongAtTop
            ? extent.minY + extent.height * 0.5
            : extent.maxY - extent.height * 0.5
        guard let ramp = CIFilter(name: "CISmoothLinearGradient", parameters: [
            "inputPoint0": CIVector(x: extent.midX, y: strongEdge),
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
            "inputPoint1": CIVector(x: extent.midX, y: weakEdge),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
        ])?.outputImage?.cropped(to: extent) else { return nil }

        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIMaskedVariableBlur", parameters: [
                "inputMask": ramp,
                kCIInputRadiusKey: blurRadius,
            ])
            .cropped(to: extent)

        guard let output = context.createCGImage(blurred, from: extent) else { return nil }
        return NSImage(cgImage: output, size: strip.size)
    }

    /// Renders a strip of the document into a bitmap of its own.
    static func renderStrip(
        strip: NSRect, scale: CGFloat, render: (NSRect) -> Void
    ) -> NSBitmapImageRep? {
        guard strip.width > 1, strip.height > 1 else { return nil }
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(strip.width * scale), pixelsHigh: Int(strip.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        representation.size = strip.size

        guard let base = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        let cgContext = base.cgContext

        NSGraphicsContext.saveGraphicsState()
        cgContext.translateBy(x: 0, y: strip.height)
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.translateBy(x: -strip.minX, y: -strip.minY)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
        render(strip)
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    // MARK: - Probes, used by --selftest

    /// Mean difference between neighbouring pixels: how sharp the content is.
    /// Blurring drops this, which is what makes a blur measurable rather than
    /// something to be taken on trust.
    static func sharpness(_ rep: NSBitmapImageRep, rows: Range<Int>) -> Double {
        var total = 0.0
        var count = 0.0
        for y in stride(from: max(rows.lowerBound, 0), to: min(rows.upperBound, rep.pixelsHigh), by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide - 1, by: 1) {
                guard let a = rep.colorAt(x: x, y: y), let b = rep.colorAt(x: x + 1, y: y) else { continue }
                total += abs(Double(a.brightnessComponent) - Double(b.brightnessComponent))
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    /// Mean darkness of a bitmap: 0 is blank, higher means more ink.
    static func darkness(_ rep: NSBitmapImageRep, rows: Range<Int>? = nil) -> Double {
        let range = rows ?? 0..<rep.pixelsHigh
        var total = 0.0
        var count = 0.0
        for y in stride(from: range.lowerBound, to: min(range.upperBound, rep.pixelsHigh), by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                total += 1 - Double(colour.brightnessComponent)
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }
}

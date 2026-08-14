import AppKit
import CoreImage

/// Draws the soft edge where content slides under the top and bottom of the
/// window: a real blur of the text underneath, ramping up toward the edge, and a
/// fade to the page colour.
///
/// This is done by re-rendering the strip and blurring it, rather than with an
/// `NSVisualEffectView` in `.withinWindow` mode. That is the obvious approach and
/// three attempts at it drew nothing at all: the effect view reports itself as
/// visible, laid out and masked, and still samples nothing from the sibling text
/// behind it. Rendering the strip is more work per frame, but it is work that can
/// be seen and tested.
struct ScrollEdgeRenderer {

    /// Reused so a blur does not allocate a context per frame.
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Gradient masks are the same for a given size, so they are cached.
    private static var masks: [String: CGImage] = [:]

    static let topHeight: CGFloat = 88
    static let bottomHeight: CGFloat = 72
    static let blurRadius: CGFloat = 9

    /// Blurs `strip` of the view and draws it back behind a fade to the page
    /// colour, both ramped so the effect is strongest at the window edge.
    static func draw(
        strip: NSRect,
        fromTop: Bool,
        pageColor: NSColor,
        scale: CGFloat,
        render: (NSRect) -> Void
    ) {
        guard strip.width > 2, strip.height > 2 else { return }

        if let blurred = blur(strip: strip, scale: scale, render: render),
           let mask = mask(size: strip.size, scale: scale, strongAtStart: fromTop),
           let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.clip(to: strip, mask: mask)
            blurred.draw(
                in: strip, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: nil)
            context.restoreGState()
        }

        // The fade sits on top of the blur, so text does not merely soften at the
        // edge, it goes.
        let gradient = NSGradient(
            colors: fromTop
                ? [pageColor, pageColor.withAlphaComponent(0)]
                : [pageColor.withAlphaComponent(0), pageColor])
        gradient?.draw(in: strip, angle: 270)
    }

    // MARK: - Pieces

    private static func blur(strip: NSRect, scale: CGFloat, render: (NSRect) -> Void) -> NSImage? {
        guard let representation = renderStrip(strip: strip, scale: scale, render: render) else {
            return nil
        }

        guard let source = CIImage(bitmapImageRep: representation) else { return nil }
        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: source.extent)

        guard let output = context.createCGImage(blurred, from: source.extent) else { return nil }
        return NSImage(cgImage: output, size: strip.size)
    }

    /// Draws the strip of the document into a bitmap of its own.
    private static func renderStrip(
        strip: NSRect, scale: CGFloat, render: (NSRect) -> Void
    ) -> NSBitmapImageRep? {
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
        // Into the strip's own coordinates, flipped to match the text view.
        cgContext.translateBy(x: 0, y: strip.height)
        cgContext.scaleBy(x: 1, y: -1)
        cgContext.translateBy(x: -strip.minX, y: -strip.minY)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
        render(strip)
        NSGraphicsContext.restoreGraphicsState()
        return representation
    }

    /// A vertical alpha ramp used to clip the blur, opaque at the window edge.
    private static func mask(size: NSSize, scale: CGFloat, strongAtStart: Bool) -> CGImage? {
        let key = "\(Int(size.width))x\(Int(size.height))@\(scale)-\(strongAtStart)"
        if let cached = masks[key] { return cached }

        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        let space = CGColorSpaceCreateDeviceGray()
        // White keeps the blur, black drops it. The strong end is the window edge.
        let stops: [CGFloat] = [0, 1]
        let components: [CGFloat] = strongAtStart ? [0, 0, 1, 1] : [1, 1, 0, 0]
        guard let gradient = CGGradient(
            colorSpace: space, colorComponents: components, locations: stops, count: 2
        ) else { return nil }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: height),
            options: [])

        let image = context.makeImage()
        if let image { masks[key] = image }
        return image
    }

    static func forgetMasks() {
        masks.removeAll()
    }

    // MARK: - Probes, used by --selftest

    struct Sample {
        /// Mean darkness of the strip, 0 for blank. Blurring text spreads its ink
        /// out, so this moves measurably when a blur really happened.
        let ink: Double
    }

    static func probeRender(strip: NSRect, scale: CGFloat, render: (NSRect) -> Void) -> Sample? {
        guard let rep = renderStrip(strip: strip, scale: scale, render: render) else { return nil }
        return Sample(ink: darkness(rep))
    }

    static func probeBlur(strip: NSRect, scale: CGFloat, render: (NSRect) -> Void) -> Sample? {
        guard let image = blur(strip: strip, scale: scale, render: render),
              let data = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: data) else { return nil }
        return Sample(ink: darkness(rep))
    }

    static func probeMask(size: NSSize, scale: CGFloat) -> Bool {
        mask(size: size, scale: scale, strongAtStart: true) != nil
    }

    /// Fraction of sampled pixels that carry ink, weighted by how dark they are.
    private static func darkness(_ rep: NSBitmapImageRep) -> Double {
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                guard let colour = rep.colorAt(x: x, y: y) else { continue }
                total += 1 - Double(colour.brightnessComponent)
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }
}

import AppKit
import CoreImage

/// Draws a soft scroll edge: a blur of the content underneath that ramps up
/// toward the window edge, then a fade to the page colour.
///
/// macOS 26.1 provides this for the top of a window through
/// `NSTitlebarAccessoryViewController.preferredScrollEdgeEffectStyle`, which is
/// what Quill uses there. AppKit exposes no equivalent for the bottom edge, and
/// nothing at all before 26.1, so this covers those cases.
///
/// Every gradient here is drawn with explicit start and end points rather than
/// an angle. Angles are measured in the current coordinate system, and this is
/// drawn into a flipped view, which is how an earlier version ended up with the
/// ramps upside down.
enum ScrollEdgeRenderer {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])
    private static var masks: [String: CGImage] = [:]

    static let blurRadius: CGFloat = 10

    /// Draws the effect into `target`, taking its content from `sourceStrip` of
    /// the document. Both rects are in flipped coordinates, so `minY` is the top.
    static func draw(
        into target: NSRect,
        sourceStrip: NSRect,
        strongAtTop: Bool,
        pageColor: NSColor,
        scale: CGFloat,
        render: (NSRect) -> Void
    ) {
        guard target.width > 2, target.height > 2,
              let context = NSGraphicsContext.current?.cgContext else { return }

        if let blurred = blur(strip: sourceStrip, scale: scale, render: render),
           let mask = mask(size: target.size, scale: scale, strongAtTop: strongAtTop) {
            context.saveGState()
            context.clip(to: target, mask: mask)
            blurred.draw(
                in: target, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: nil)
            context.restoreGState()
        }

        // The fade sits over the blur, so text at the very edge goes rather than
        // merely softening.
        drawFade(in: target, color: pageColor, strongAtTop: strongAtTop, context: context)
    }

    private static func drawFade(
        in rect: NSRect, color: NSColor, strongAtTop: Bool, context: CGContext
    ) {
        guard let opaque = color.usingColorSpace(.sRGB) else { return }
        let clear = opaque.withAlphaComponent(0)
        let colors = strongAtTop
            ? [opaque.cgColor, clear.cgColor]
            : [clear.cgColor, opaque.cgColor]

        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: [0, 1]
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

    private static func blur(
        strip: NSRect, scale: CGFloat, render: (NSRect) -> Void
    ) -> NSImage? {
        guard let representation = renderStrip(strip: strip, scale: scale, render: render),
              let source = CIImage(bitmapImageRep: representation) else { return nil }

        let blurred = source
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blurRadius])
            .cropped(to: source.extent)

        guard let output = context.createCGImage(blurred, from: source.extent) else { return nil }
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

    /// A vertical alpha ramp used to clip the blur, opaque at the window edge.
    private static func mask(size: NSSize, scale: CGFloat, strongAtTop: Bool) -> CGImage? {
        let key = "\(Int(size.width))x\(Int(size.height))@\(scale)-\(strongAtTop)"
        if let cached = masks[key] { return cached }

        let width = max(Int(size.width * scale), 1)
        let height = max(Int(size.height * scale), 1)
        let space = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        // A CGContext is bottom-up, so y == 0 here is the *bottom* of the strip.
        // White keeps the blur, black drops it.
        let components: [CGFloat] = strongAtTop ? [0, 1] : [1, 0]
        guard let gradient = CGGradient(
            colorSpace: space, colorComponents: components, locations: [0, 1], count: 2
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

    static func forgetMasks() { masks.removeAll() }

    // MARK: - Probes, used by --selftest

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

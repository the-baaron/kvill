import AppKit

/// Draws every specimen button onto one sheet, so the typography picker can be
/// looked at without the glass popover that will not render off screen.
enum SpecimenSheet {

    static func render(to path: String) -> Int32 {
        var kinds: [SpecimenButton.Kind] = TypographyPreset.all.map { .typeface($0) }
        kinds += TextSize.allCases.map { .size($0) }
        kinds += LineWidth.allCases.map { .width($0) }

        let gap: CGFloat = 10
        let width = kinds.reduce(gap) { $0 + $1.box.width + gap }
        let size = NSSize(width: width, height: 60)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 3), pixelsHigh: Int(size.height * 3),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return 1 }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        var x = gap
        for (index, kind) in kinds.enumerated() {
            let button = SpecimenButton(kind: kind, target: nil, action: #selector(NSView.layout))
            button.frame = NSRect(x: x, y: 10, width: kind.box.width, height: kind.box.height)
            // One of each group drawn as chosen, to show the selection ring too.
            button.isChosen = index == 0 || index == TypographyPreset.all.count
            NSGraphicsContext.current?.saveGraphicsState()
            let shift = NSAffineTransform()
            shift.translateX(by: button.frame.minX, yBy: button.frame.minY)
            shift.concat()
            button.draw(button.bounds)
            NSGraphicsContext.current?.restoreGraphicsState()
            x += kind.box.width + gap
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        return 0
    }
}

import AppKit

/// A miniature page in a theme's own colours: its background, a heading bar, a
/// line of body text and its accent. It reads as "what my document will look
/// like", which a plain colour dot does not.
final class PaletteSwatchButton: NSButton {

    static let size = NSSize(width: 58, height: 40)

    let palette: ColorTheme
    var isSelectedSwatch = false {
        didSet { needsDisplay = true }
    }

    init(palette: ColorTheme, target: AnyObject?, action: Selector) {
        self.palette = palette
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = palette.name
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.size.width),
            heightAnchor.constraint(equalToConstant: Self.size.height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1.5, dy: 1.5)
        let radius: CGFloat = 7
        let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        palette.background.setFill()
        path.fill()

        // A translucent theme is shown as one: the page colour is drawn over a
        // hint of what would be behind it.
        if palette.isTranslucent {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            NSColor.systemBlue.withAlphaComponent(0.35).setFill()
            NSRect(x: box.minX, y: box.minY, width: box.width, height: box.height * 0.5).fill()
            palette.background.withAlphaComponent(palette.pageAlpha).setFill()
            box.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        let inset: CGFloat = 7
        let width = box.width - inset * 2
        bar(x: box.minX + inset, y: box.maxY - 13, width: width * 0.66, height: 4,
            color: palette.heading)
        bar(x: box.minX + inset, y: box.maxY - 21, width: width, height: 2.5,
            color: palette.text.withAlpha(0.5))
        bar(x: box.minX + inset, y: box.maxY - 27, width: width * 0.82, height: 2.5,
            color: palette.text.withAlpha(0.5))
        bar(x: box.minX + inset, y: box.maxY - 34, width: width * 0.4, height: 3,
            color: palette.accent)

        if isSelectedSwatch {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
                xRadius: radius + 1, yRadius: radius + 1)
            ring.lineWidth = 2
            ring.stroke()
        } else {
            palette.text.withAlpha(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func bar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: width, height: height),
            xRadius: height / 2, yRadius: height / 2
        ).fill()
    }
}

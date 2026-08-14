import AppKit

/// A small preview tile for one colour theme: the theme's own background with
/// its own heading, body and accent colours drawn on it.
final class PaletteSwatchButton: NSButton {

    let palette: ColorTheme
    var isSelectedSwatch: Bool = false {
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
        setContentHuggingPriority(.required, for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 46),
            heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7)
        palette.background.setFill()
        path.fill()

        // Three stacked bars standing in for a heading, a line of body text and
        // an accent, so the swatch reads as "what my document will look like".
        let inset: CGFloat = 7
        let width = box.width - inset * 2
        drawBar(x: box.minX + inset, y: box.maxY - 12, width: width * 0.72, height: 3.5,
                color: palette.heading)
        drawBar(x: box.minX + inset, y: box.maxY - 19, width: width, height: 2.5,
                color: palette.text.withAlpha(0.55))
        drawBar(x: box.minX + inset, y: box.maxY - 25, width: width * 0.45, height: 2.5,
                color: palette.accent)

        if isSelectedSwatch {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8)
            ring.lineWidth = 2
            ring.stroke()
        } else {
            palette.text.withAlpha(0.18).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: width, height: height),
            xRadius: height / 2, yRadius: height / 2
        ).fill()
    }
}

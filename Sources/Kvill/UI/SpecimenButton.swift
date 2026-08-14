import AppKit

/// A picker that shows the thing rather than naming it.
///
/// Choosing a typeface from a list of names asks you to remember what "Grotesk"
/// looks like here. Choosing it from a specimen does not. The palette section
/// already works this way, with a miniature page per theme; these are the same
/// idea for the typeface, the text size and the column width.
final class SpecimenButton: NSButton {

    enum Kind {
        /// Letters set in the face itself, over the current page colour.
        case typeface(TypographyPreset)
        /// One letter at the size it would be, relative to the others.
        case size(TextSize)
        /// Lines of text at that measure, drawn in a page.
        case width(LineWidth)

        var identifier: String {
            switch self {
            case .typeface(let preset): return preset.id
            case .size(let size): return size.rawValue
            case .width(let width): return width.rawValue
            }
        }

        var label: String {
            switch self {
            case .typeface(let preset): return preset.name
            case .size(let size): return size.name
            case .width(let width): return width.name
            }
        }

        var box: NSSize {
            switch self {
            case .typeface: return NSSize(width: 58, height: 40)
            case .size: return NSSize(width: 42, height: 40)
            case .width: return NSSize(width: 42, height: 40)
            }
        }
    }

    let kind: Kind
    var isChosen = false { didSet { needsDisplay = true } }

    private var colors: ColorTheme { ThemeManager.shared.theme.colors }

    init(kind: Kind, target: AnyObject?, action: Selector) {
        self.kind = kind
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = kind.label
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: kind.box.width),
            heightAnchor.constraint(equalToConstant: kind.box.height),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1.5, dy: 1.5)
        let radius: CGFloat = 7
        let page = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)

        colors.background.setFill()
        page.fill()

        switch kind {
        case .typeface(let preset):
            draw(specimen: "Ag", in: box, using: preset)
        case .size(let size):
            draw(specimen: "A", in: box, using: ThemeManager.shared.theme.preset,
                 scale: 0.42 + CGFloat(TextSize.allCases.firstIndex(of: size) ?? 0) * 0.13)
        case .width(let width):
            drawMeasure(width, in: box)
        }

        if isChosen {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
                xRadius: radius + 1, yRadius: radius + 1)
            ring.lineWidth = 2
            ring.stroke()
        } else {
            colors.text.withAlpha(0.18).setStroke()
            page.lineWidth = 1
            page.stroke()
        }
    }

    /// Letters set in the face being offered, sized to sit inside the box.
    private func draw(specimen: String, in box: NSRect,
                      using preset: TypographyPreset, scale: CGFloat = 0.55) {
        let font = FontBuilder.font(preset.headingFamily, size: box.height * scale,
                                    weight: preset.headingWeight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: colors.heading,
        ]
        let size = (specimen as NSString).size(withAttributes: attributes)
        (specimen as NSString).draw(
            at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2),
            withAttributes: attributes)
    }

    /// A page with lines of text on it, as wide as that measure would set them.
    private func drawMeasure(_ width: LineWidth, in box: NSRect) {
        let fraction: CGFloat
        switch LineWidth.allCases.firstIndex(of: width) ?? 1 {
        case 0: fraction = 0.44
        case 1: fraction = 0.66
        default: fraction = 0.86
        }
        let lineWidth = (box.width - 12) * fraction
        let left = box.midX - lineWidth / 2
        for (index, y) in [11, 17, 23, 29].enumerated() {
            // The last line stops short, the way a paragraph's does.
            let run = index == 3 ? lineWidth * 0.55 : lineWidth
            colors.text.withAlpha(index == 0 ? 0.75 : 0.4).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: left, y: box.maxY - CGFloat(y), width: run, height: 2.5),
                xRadius: 1.25, yRadius: 1.25
            ).fill()
        }
    }
}

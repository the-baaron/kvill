import AppKit
import CoreImage

/// The soft edge where content slides under the top or bottom of the window:
/// a backdrop blur that ramps up toward the edge, plus a fade to the page colour.
///
/// The blur is a `CALayer` background filter, which blurs the sibling content
/// behind it inside the same window, and a gradient layer mask turns that flat
/// blur into a progressive one.
final class ScrollEdgeEffectView: NSView {

    enum Edge {
        case top
        case bottom
    }

    private let edge: Edge
    private let blurLayer = CALayer()
    private let blurMask = CAGradientLayer()
    private let fadeLayer = CAGradientLayer()

    var theme: Theme {
        didSet { applyTheme() }
    }

    init(edge: Edge, theme: Theme) {
        self.edge = edge
        self.theme = theme
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = true

        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(11.0, forKey: kCIInputRadiusKey)
            blurLayer.backgroundFilters = [blur]
        }
        blurLayer.masksToBounds = true
        blurLayer.mask = blurMask
        layer?.addSublayer(blurLayer)
        layer?.addSublayer(fadeLayer)

        // The gradients run bottom-to-top; which end is "strong" depends on
        // which edge of the window this view is pinned to.
        let strongAtTop = edge == .top
        blurMask.startPoint = CGPoint(x: 0.5, y: 0)
        blurMask.endPoint = CGPoint(x: 0.5, y: 1)
        blurMask.colors = strongAtTop
            ? [NSColor.clear.cgColor, NSColor.black.cgColor]
            : [NSColor.black.cgColor, NSColor.clear.cgColor]
        blurMask.locations = strongAtTop ? [0.0, 0.85] : [0.15, 1.0]

        fadeLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fadeLayer.endPoint = CGPoint(x: 0.5, y: 1)

        alphaValue = 0
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        // Layer frames are set without implicit animation so resizing the window
        // does not leave the gradients lagging behind the view.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        blurLayer.frame = bounds
        blurMask.frame = bounds
        fadeLayer.frame = bounds
        CATransaction.commit()
    }

    private func applyTheme() {
        let background = theme.colors.background
        let solid = background.withAlphaComponent(1).cgColor
        let clear = background.withAlphaComponent(0).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeLayer.colors = edge == .top ? [clear, solid] : [solid, clear]
        fadeLayer.locations = edge == .top ? [0.35, 1.0] : [0.0, 0.65]
        CATransaction.commit()
    }

    /// Fades the whole effect in only when there is content sliding under it, so
    /// a short document is not blurred against empty space.
    func setActive(_ active: Bool) {
        let target: CGFloat = active ? 1 : 0
        guard abs(alphaValue - target) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = target
        }
    }

    /// Chrome only: never swallow a click meant for the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

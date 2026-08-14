import AppKit

/// The soft edge where content slides under the top or bottom of the window: a
/// blur that ramps up toward the edge, plus a fade to the page colour.
///
/// The blur is an `NSVisualEffectView` in `.withinWindow` blending mode, which
/// samples the sibling content behind it rather than the desktop. Its
/// `maskImage` is a vertical alpha gradient, which is what turns a flat blur
/// into a progressive one.
///
/// `CALayer.backgroundFilters` looks like the natural fit for this and is what
/// the first version used, but AppKit silently ignores it for layer-backed
/// views on current macOS, so nothing was drawn.
final class ScrollEdgeEffectView: NSView {

    enum Edge {
        case top
        case bottom
    }

    private let edge: Edge
    private let blur = NSVisualEffectView()
    private let fade = NSView()
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

        blur.blendingMode = .withinWindow
        blur.material = .headerView
        blur.state = .active
        blur.translatesAutoresizingMaskIntoConstraints = false

        fade.wantsLayer = true
        fade.layer?.addSublayer(fadeLayer)
        fade.translatesAutoresizingMaskIntoConstraints = false

        addSubview(blur)
        addSubview(fade)

        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            fade.leadingAnchor.constraint(equalTo: leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: trailingAnchor),
            fade.topAnchor.constraint(equalTo: topAnchor),
            fade.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // The gradients run bottom-to-top; which end is strong depends on which
        // edge of the window this view is pinned to.
        fadeLayer.startPoint = CGPoint(x: 0.5, y: 0)
        fadeLayer.endPoint = CGPoint(x: 0.5, y: 1)

        // Always on. Gating this on scroll position added a way for the whole
        // effect to silently never appear, and it costs nothing to leave up:
        // over the page's own colour the fade is invisible anyway.
        alphaValue = 1
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeLayer.frame = bounds
        CATransaction.commit()
        updateMask()
    }

    /// A vertical alpha ramp, opaque at the window edge and clear where the
    /// effect should stop. `NSVisualEffectView` multiplies its blur by this.
    private func updateMask() {
        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }

        let strongAtTop = edge == .top
        let image = NSImage(size: NSSize(width: 8, height: size.height), flipped: false) { rect in
            // The mask is read from the alpha channel, so it has to be built in a
            // colour space that carries one. A grey space silently loses it and
            // the whole effect renders at full strength or not at all.
            let gradient = NSGradient(
                colors: [
                    NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0),
                    NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                ],
                atLocations: [0, 1],
                colorSpace: .sRGB)
            // Angle 90 fills upward, so the top edge is the opaque end.
            gradient?.draw(in: rect, angle: strongAtTop ? 90 : 270)
            return true
        }
        image.capInsets = NSEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        image.resizingMode = .stretch
        blur.maskImage = image
    }

    private func applyTheme() {
        let background = theme.colors.page
        let solid = background.cgColor
        let clear = background.withAlphaComponent(0).cgColor

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeLayer.colors = edge == .top ? [clear, solid] : [solid, clear]
        fadeLayer.locations = edge == .top ? [0.22, 1.0] : [0.0, 0.78]
        CATransaction.commit()
    }

    /// Strengthens the effect once content is actually sliding under the edge.
    func setActive(_ active: Bool) {
        let target: CGFloat = active ? 1 : 0.7
        guard abs(alphaValue - target) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = target
        }
    }

    /// Whether the progressive blur's alpha ramp has been built.
    var hasMask: Bool { blur.maskImage != nil }

    /// Chrome only: never swallow a click meant for the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

import AppKit

/// The soft edge where content slides under the top or bottom of the window.
///
/// It is pinned to the window, not to the document, which is the whole point:
/// an earlier version drew this inside the text view, and because the text view
/// *is* the scrolling document, the effect scrolled away with the text.
///
/// The blur is produced by re-rendering the strip of document underneath and
/// running it through `CIGaussianBlur`, then clipping it with a gradient so it
/// ramps toward the window edge. An `NSVisualEffectView` in `.withinWindow` mode
/// is the obvious way to do this and drew nothing at all across three attempts:
/// it reports itself visible, laid out and masked, and samples nothing.
final class ScrollEdgeView: NSView {

    enum Edge {
        case top
        case bottom
    }

    private let edge: Edge
    /// The document this edge softens. Weak: the editor owns it.
    weak var source: EditorTextView?

    var theme: Theme {
        didSet { needsDisplay = true }
    }

    /// Whether content is currently sliding under this edge.
    private(set) var isEngaged = false

    init(edge: Edge, theme: Theme) {
        self.edge = edge
        self.theme = theme
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Matching the text view's orientation keeps every rect in one convention.
    override var isFlipped: Bool { true }

    /// Chrome only: never swallow a click meant for the text underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Called when the viewport moves, since the content underneath changed.
    func viewportMoved() {
        let engaged = computeEngaged()
        if engaged != isEngaged {
            isEngaged = engaged
        }
        needsDisplay = true
    }

    private func computeEngaged() -> Bool {
        guard let source, let clip = source.enclosingScrollView?.contentView else { return false }
        switch edge {
        case .top:
            return clip.bounds.origin.y > 2
        case .bottom:
            let visible = source.visibleRect
            return visible.maxY < source.frame.height - 2
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isEngaged, let source, bounds.width > 2, bounds.height > 2 else { return }

        let scale = window?.backingScaleFactor ?? 2
        let strip = convert(bounds, to: source)
        let page = theme.colors.page

        ScrollEdgeRenderer.draw(
            into: bounds,
            sourceStrip: strip,
            strongAtTop: edge == .top,
            pageColor: page,
            scale: scale,
            render: { rect in source.renderPage(rect) })
    }

    /// Renders the effect into a bitmap so a test can measure which end of it is
    /// actually opaque, rather than taking the orientation on trust.
    /// Renders the document strip and then the effect over it, exactly as the
    /// screen shows it. Rendering the effect alone would leave the unmasked part
    /// of the bitmap transparent, which a measurement reads as solid black.
    func renderForTest(size: NSSize, scale: CGFloat = 2, fade: Bool = true) -> NSBitmapImageRep? {
        guard let source else { return nil }
        // Target and source are the same rect here, so the bitmap's coordinate
        // space matches the document's. On screen they differ, because the view
        // is in viewport coordinates and the document is not.
        let strip = NSRect(x: 0, y: 200, width: size.width, height: size.height)

        return ScrollEdgeRenderer.renderStrip(strip: strip, scale: scale) { _ in
            // The content underneath.
            source.renderPage(strip)
            // Then the edge over the top of it.
            ScrollEdgeRenderer.draw(
                into: strip,
                sourceStrip: strip,
                strongAtTop: self.edge == .top,
                pageColor: self.theme.colors.page,
                scale: scale,
                fade: fade,
                render: { rect in source.renderPage(rect) })
        }
    }
}

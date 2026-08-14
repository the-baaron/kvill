import AppKit

/// A clip view that allows scrolling past the end of the document.
///
/// Typewriter mode needs the last line to be able to reach the middle of the
/// window, which means the view has to scroll further than the text is tall.
/// The obvious route, `NSScrollView.contentInsets`, is wrong here: it insets the
/// clip view inside the scroll view, so a bottom inset of half the window
/// halves the visible text area instead of adding slack below it.
final class TypewriterClipView: NSClipView {

    /// Extra scrollable space below the document, in points.
    var bottomSlack: CGFloat = 0 {
        didSet {
            guard bottomSlack != oldValue else { return }
            // Re-clamp in case the current position is now out of range.
            scroll(to: bounds.origin)
            enclosingScrollView?.reflectScrolledClipView(self)
        }
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard bottomSlack > 0, let document = documentView else { return rect }

        let maxY = max(0, document.frame.height + bottomSlack - rect.height)
        rect.origin.y = min(max(proposedBounds.origin.y, 0), maxY)
        return rect
    }
}

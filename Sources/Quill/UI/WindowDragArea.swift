import AppKit

/// An invisible strip along the top of the window that drags it.
///
/// The window uses a full-size content view so the page runs under a
/// transparent title bar, which means the text view covers the area you would
/// normally grab. This sits above the text and claims the drag; any control
/// placed on top of it, such as the display options bar, still takes its own
/// clicks because it is later in the subview order.
final class WindowDragArea: NSView {

    /// A little deeper than the standard title bar, so there is something to
    /// grab without having to aim.
    static let height: CGFloat = 44

    /// The drag is run explicitly rather than left to `mouseDownCanMoveWindow`,
    /// which is unreliable for a layer-backed view inside a window with a
    /// full-size content view: the window server never starts the drag and the
    /// title bar area simply does not respond.
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard let window else {
            super.mouseDown(with: event)
            return
        }
        if event.clickCount == 2 {
            // Double-clicking the title bar zooms, as it does anywhere else.
            window.performZoom(nil)
            return
        }
        window.performDrag(with: event)
    }

    /// Chrome, not content: never show a text cursor over it.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

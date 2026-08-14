import AppKit

/// An invisible strip along the top of the window that drags it.
///
/// The window uses a full-size content view so the page runs under a
/// transparent title bar, which means the text view covers the area you would
/// normally grab. This sits above the text and claims the drag; any control
/// placed on top of it, such as the display options button, still takes its own
/// clicks because it is later in the subview order.
final class WindowDragArea: NSView {

    /// Matches the standard title bar, with a little extra to grab at.
    static let height: CGFloat = 38

    override var mouseDownCanMoveWindow: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Never take a click meant for a subview; there are none, so this only
        // ever returns self or nil.
        super.hitTest(point)
    }

    /// A double click in the title bar zooms the window, as it does anywhere else.
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
            return
        }
        super.mouseDown(with: event)
    }
}

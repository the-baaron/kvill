import AppKit

/// A clip view that lets the document be scrolled past its last line.
///
/// There is nothing in it. The slack is not a scrolling rule at all: the text
/// view is simply made taller than its text, by `EditorViewController`, and the
/// scroll view then scrolls to the bottom of that as it would for any document.
/// Constraining the bounds instead looked like the tidier idea and was not: it
/// is honoured on some routes into scrolling and not others, so how far you
/// could scroll depended on how you scrolled.
///
/// The type is kept because the editor asks for it by name, and because the next
/// person to reach for `constrainBoundsRect` should read the paragraph above.
final class TypewriterClipView: NSClipView {}

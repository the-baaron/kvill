import AppKit

/// The small control that appears at a table's top corner while the caret is
/// inside it, and opens the table editor.
///
/// Without it the panel exists only on a keyboard shortcut, which is another way
/// of saying it does not exist. It sits over the page rather than in the toolbar
/// because it belongs to one table, not to the document.
final class TableBadgeView: NSView {

    var onClick: (() -> Void)?

    private let button = NSButton()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        button.image = NSImage(
            systemSymbolName: "tablecells", accessibilityDescription: "Edit table")
        button.imagePosition = .imageLeading
        button.title = "Edit"
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.target = self
        button.action = #selector(clicked)
        button.toolTip = "Edit this table  ⌃⌘T"
        button.translatesAutoresizingMaskIntoConstraints = false

        let glass = GlassContainerView(content: button, cornerRadius: 11, padding: 7)
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func clicked() {
        onClick?()
    }

    /// Chrome, not content: no text cursor over it.
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}

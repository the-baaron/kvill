import AppKit

/// The formatting bar that appears over a selection. Each button sends a plain
/// action up the responder chain, so it drives exactly the same code paths as
/// the Format menu and its keyboard shortcuts.
final class SelectionToolbarView: NSView {

    private struct Command {
        let symbol: String
        let label: String
        let selector: Selector
        /// Drawn as a text label instead of a symbol, for the heading buttons.
        var text: String?
    }

    private static let commands: [Command] = [
        Command(symbol: "bold", label: "Bold",
                selector: #selector(EditorViewController.toggleBold(_:))),
        Command(symbol: "italic", label: "Italic",
                selector: #selector(EditorViewController.toggleItalic(_:))),
        Command(symbol: "strikethrough", label: "Strikethrough",
                selector: #selector(EditorViewController.toggleStrikethrough(_:))),
        Command(symbol: "highlighter", label: "Highlight",
                selector: #selector(EditorViewController.toggleHighlight(_:))),
        Command(symbol: "chevron.left.forwardslash.chevron.right", label: "Inline code",
                selector: #selector(EditorViewController.toggleInlineCode(_:))),
        Command(symbol: "link", label: "Link",
                selector: #selector(EditorViewController.insertLink(_:))),
        Command(symbol: "", label: "Heading 1",
                selector: #selector(EditorViewController.setHeading1(_:)), text: "H1"),
        Command(symbol: "", label: "Heading 2",
                selector: #selector(EditorViewController.setHeading2(_:)), text: "H2"),
        Command(symbol: "list.bullet", label: "Bulleted list",
                selector: #selector(EditorViewController.toggleBulletList(_:))),
        Command(symbol: "checklist", label: "Task list",
                selector: #selector(EditorViewController.toggleTaskList(_:))),
        Command(symbol: "text.quote", label: "Blockquote",
                selector: #selector(EditorViewController.toggleBlockquote(_:))),
    ]

    /// Indices after which a divider is drawn.
    private static let dividersAfter: Set<Int> = [5, 7]

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = []
        for (index, command) in Self.commands.enumerated() {
            views.append(button(for: command, tag: index))
            if Self.dividersAfter.contains(index) { views.append(divider()) }
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)

        let glass = GlassContainerView(content: stack, cornerRadius: 19, padding: 7)
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func button(for command: Command, tag: Int) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.tag = tag
        button.toolTip = command.label
        button.target = self
        button.action = #selector(performCommand(_:))
        button.translatesAutoresizingMaskIntoConstraints = false

        if let text = command.text {
            button.title = text
            button.font = .systemFont(ofSize: 11.5, weight: .semibold)
        } else {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: command.symbol, accessibilityDescription: command.label)
            button.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 12.5, weight: .medium)
        }

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
        return button
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 15),
        ])
        return line
    }

    @objc private func performCommand(_ sender: NSButton) {
        guard sender.tag >= 0, sender.tag < Self.commands.count else { return }
        NSApp.sendAction(Self.commands[sender.tag].selector, to: nil, from: sender)
    }
}

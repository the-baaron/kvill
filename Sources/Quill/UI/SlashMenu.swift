import AppKit

/// One thing the slash menu can insert.
struct SlashCommand {
    let title: String
    let symbol: String
    /// Words that should also find this entry, so "bullet" finds the list and
    /// "h1" finds the heading.
    let keywords: [String]
    /// Run against the editor once the `/query` has been taken back out.
    let run: (EditorViewController) -> Void

    func matches(_ query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let needle = query.lowercased()
        if title.lowercased().hasPrefix(needle) { return true }
        if title.lowercased().contains(needle) { return true }
        return keywords.contains { $0.hasPrefix(needle) }
    }
}

extension SlashCommand {

    /// Everything offered, in the order it is offered. Blocks first, because a
    /// slash at the start of a line is nearly always about to make one.
    static let all: [SlashCommand] = [
        SlashCommand(title: "Heading 1", symbol: "textformat.size.larger",
                     keywords: ["h1", "title"]) { $0.setHeading1(nil) },
        SlashCommand(title: "Heading 2", symbol: "textformat.size",
                     keywords: ["h2", "subtitle"]) { $0.setHeading2(nil) },
        SlashCommand(title: "Heading 3", symbol: "textformat.size.smaller",
                     keywords: ["h3"]) { $0.setHeading3(nil) },
        SlashCommand(title: "Bulleted List", symbol: "list.bullet",
                     keywords: ["ul", "bullet", "unordered"]) { $0.toggleBulletList(nil) },
        SlashCommand(title: "Numbered List", symbol: "list.number",
                     keywords: ["ol", "ordered", "number"]) { $0.toggleNumberedList(nil) },
        SlashCommand(title: "Task List", symbol: "checklist",
                     keywords: ["todo", "check", "task"]) { $0.toggleTaskList(nil) },
        SlashCommand(title: "Table", symbol: "tablecells",
                     keywords: ["grid", "sheet"]) { $0.insertTable(nil) },
        SlashCommand(title: "Code Block", symbol: "chevron.left.forwardslash.chevron.right",
                     keywords: ["fence", "pre"]) { $0.insertCodeBlock(nil) },
        SlashCommand(title: "Quote", symbol: "text.quote",
                     keywords: ["blockquote", "cite"]) { $0.toggleBlockquote(nil) },
        SlashCommand(title: "Divider", symbol: "minus",
                     keywords: ["rule", "hr", "line", "separator"]) { $0.insertHorizontalRule(nil) },
        SlashCommand(title: "Image", symbol: "photo",
                     keywords: ["picture", "img"]) { $0.insertImage(nil) },
        SlashCommand(title: "Link", symbol: "link",
                     keywords: ["url", "href"]) { $0.insertLink(nil) },
        SlashCommand(title: "Footnote", symbol: "text.badge.star",
                     keywords: ["note", "ref"]) { $0.insertFootnote(nil) },
        SlashCommand(title: "Note Callout", symbol: "info.circle",
                     keywords: ["callout", "info"]) { $0.insertCalloutNote(nil) },
        SlashCommand(title: "Tip Callout", symbol: "lightbulb",
                     keywords: ["callout", "hint"]) { $0.insertCalloutTip(nil) },
        SlashCommand(title: "Important Callout", symbol: "exclamationmark.circle",
                     keywords: ["callout"]) { $0.insertCalloutImportant(nil) },
        SlashCommand(title: "Warning Callout", symbol: "exclamationmark.triangle",
                     keywords: ["callout", "caution"]) { $0.insertCalloutWarning(nil) },
        SlashCommand(title: "Caution Callout", symbol: "exclamationmark.octagon",
                     keywords: ["callout", "danger"]) { $0.insertCalloutCaution(nil) },
    ]

    static func matching(_ query: String) -> [SlashCommand] {
        all.filter { $0.matches(query) }
    }
}

/// The list that drops out of a `/` typed in the document.
///
/// It is a non-activating panel rather than a popover, so the keyboard stays
/// with the text view: you keep typing into your document and the list narrows
/// under you, which is what makes it feel like part of the text rather than a
/// dialogue you have been sent to.
final class SlashMenuPanel: NSPanel {

    /// Called with the chosen command, or nil when the menu was dismissed.
    var onChoose: ((SlashCommand?) -> Void)?

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var commands: [SlashCommand] = []

    private static let rowHeight: CGFloat = 30
    private static let visibleRows = 7
    private static let width: CGFloat = 248
    private static let padding: CGFloat = 8

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let column = NSTableColumn(identifier: .init("command"))
        column.width = Self.width - Self.padding * 2 - 8
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.gridStyleMask = []
        // The stock highlight is a square wash the width of the table. A menu
        // wants a rounded pill inside the padding, so the row draws its own.
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clicked)

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // A window's content view is positioned by the frame, and
        // GlassContainerView turns its own autoresizing off for Auto Layout, so
        // it cannot be the content view directly: it would be given no size at
        // all and the panel would come up empty. It goes inside a plain one.
        let glass = GlassContainerView(
            content: scrollView, cornerRadius: 16, padding: Self.padding)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 200))
        host.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            glass.topAnchor.constraint(equalTo: host.topAnchor),
            glass.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        contentView = host
    }

    /// Panels that take key focus would pull the caret out of the document.
    override var canBecomeKey: Bool { false }

    var rowHeightForTest: CGFloat { tableView.rowHeight }

    /// The highlight is drawn by the row and the colours are set by the cell, so
    /// "is it highlighted" means both agree, which is what this reports.
    var selectedRowIsHighlightedForTest: Bool {
        guard tableView.selectedRow >= 0 else { return false }
        let row = tableView.rowView(atRow: tableView.selectedRow, makeIfNecessary: true)
        let cell = tableView.view(atColumn: 0, row: tableView.selectedRow, makeIfNecessary: true)
        return row is SlashRowView && (cell as? NSTableCellView)?.textField?.textColor == .white
    }

    // MARK: - Contents

    /// Returns false when nothing matches, which is the caller's cue to close:
    /// an empty menu is just something covering the text.
    @discardableResult
    func update(query: String) -> Bool {
        commands = SlashCommand.matching(query)
        tableView.reloadData()
        guard !commands.isEmpty else { return false }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        resize()
        return true
    }

    private func resize() {
        let rows = min(Self.visibleRows, commands.count)
        let height = CGFloat(rows) * (Self.rowHeight + 2) + Self.padding * 2
        setContentSize(NSSize(width: Self.width, height: height))
    }

    /// Puts the menu under the caret, or above it when there is no room below.
    func position(below caret: NSRect, in view: NSView) {
        guard let window = view.window else { return }
        let inWindow = view.convert(caret, to: nil)
        var origin = window.convertPoint(toScreen: NSPoint(x: inWindow.minX, y: inWindow.minY))
        origin.y -= frame.height + 6

        if let screen = window.screen, origin.y < screen.visibleFrame.minY {
            origin.y = window.convertPoint(toScreen: NSPoint(x: 0, y: inWindow.maxY)).y + 6
        }
        if let screen = window.screen {
            origin.x = min(origin.x, screen.visibleFrame.maxX - frame.width - 8)
        }
        setFrameOrigin(origin)
    }

    // MARK: - Keyboard, driven from the text view

    func moveSelection(by delta: Int) {
        guard !commands.isEmpty else { return }
        let next = max(0, min(commands.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func chooseSelected() {
        let row = tableView.selectedRow
        onChoose?(row >= 0 && row < commands.count ? commands[row] : nil)
    }

    @objc private func clicked() {
        chooseSelected()
    }
}

// MARK: - Rows

extension SlashMenuPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { commands.count }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard row < commands.count else { return nil }
        let command = commands[row]

        let identifier = NSUserInterfaceItemIdentifier("row")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self)
            as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            // The same weight the floating formatting bar uses, so the two read
            // as parts of one interface.
            image.symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 12.5, weight: .medium)
            cell.addSubview(image)
            cell.imageView = image

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            cell.textField = label

            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 17),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 9),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let chosen = row == tableView.selectedRow
        cell.imageView?.image = NSImage(
            systemSymbolName: command.symbol, accessibilityDescription: nil)
        cell.imageView?.contentTintColor = chosen ? .white : .secondaryLabelColor
        cell.textField?.stringValue = command.title
        cell.textField?.textColor = chosen ? .white : .labelColor
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SlashRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // The label and symbol change colour with the highlight, so the rows on
        // either side of a move both have to be redrawn.
        tableView.enumerateAvailableRowViews { view, index in
            view.needsDisplay = true
            (tableView.view(atColumn: 0, row: index, makeIfNecessary: false) as? NSTableCellView)
                .map { cell in
                    let chosen = index == tableView.selectedRow
                    cell.textField?.textColor = chosen ? .white : .labelColor
                    cell.imageView?.contentTintColor = chosen ? .white : .secondaryLabelColor
                }
        }
    }
}

/// A menu row: a rounded pill in the accent colour, drawn whether or not the
/// panel is the key window, because this panel never becomes key.
final class SlashRowView: NSTableRowView {

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let box = bounds.insetBy(dx: 2, dy: 0)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
    }

    override var isEmphasized: Bool {
        get { true }
        set { _ = newValue }
    }
}

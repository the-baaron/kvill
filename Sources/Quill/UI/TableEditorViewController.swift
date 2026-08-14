import AppKit

/// Edits a Markdown table as a table.
///
/// The document shows a table as aligned monospace source, which is honest and
/// readable but is still text: to add a column you would type pipes into four
/// separate lines and count spaces. This is the other half. It is an ordinary
/// `NSTableView` in a popover, so cells tab, rows select, and the keyboard works
/// the way it does everywhere else on the system. Every change writes the padded
/// Markdown straight back into the document, so there is no apply step and no
/// separate copy of the truth.
final class TableEditorViewController: NSViewController {

    /// The table as data. Row 0 is the header.
    private var rows: [[String]]
    private var alignments: [TableFormatter.Alignment]

    /// Called with the rendered Markdown whenever anything changes.
    private let onChange: (String) -> Void

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let alignmentControl = NSSegmentedControl()

    /// Column the alignment buttons act on: whichever one was last edited.
    private var focusedColumn = 0

    private static let rowHeight: CGFloat = 26

    init(table: TableFormatter.Table, onChange: @escaping (String) -> Void) {
        var rows = table.rows
        let columns = max(1, table.columnCount)
        // Ragged rows are legal Markdown but make a poor table view, so every
        // row is squared off to the same width before it is shown.
        for index in rows.indices {
            while rows[index].count < columns { rows[index].append("") }
            if rows[index].count > columns { rows[index].removeLast(rows[index].count - columns) }
        }
        if rows.isEmpty { rows = [Array(repeating: "", count: columns)] }

        var alignments = table.alignments
        while alignments.count < columns { alignments.append(.none) }

        self.rows = rows
        self.alignments = alignments
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Layout

    override func loadView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = Self.rowHeight
        tableView.usesAlternatingRowBackgroundColors = false
        // The popover paints the ground; the table drawing its own on top of it
        // would put a slab of the wrong colour inside the panel.
        tableView.backgroundColor = .clear
        tableView.style = .inset
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .regular
        // The Markdown header is row 0, drawn in bold, so a second header on top
        // of it would be a header for the header.
        tableView.headerView = nil
        rebuildColumns()

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let bar = makeToolbar()

        let stack = NSStackView(views: [scrollView, bar])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)

        view = stack
        updateAlignmentControl()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Straight into the first cell: the point of opening this is to type.
        guard !rows.isEmpty, !alignments.isEmpty else { return }
        view.window?.makeFirstResponder(tableView)
        tableView.editColumn(0, row: 0, with: nil, select: true)
    }

    /// Size the popover asks for. Wide enough to read, never taller than a
    /// sensible popover.
    var preferredSize: NSSize {
        let columns = tableView.tableColumns.reduce(CGFloat(0)) { $0 + $1.width + 6 }
        // The inset table style keeps its own margin inside the scroll view, so
        // the panel has to be wider than the columns alone.
        let width = min(760, max(360, columns + 60))
        let height = min(420, CGFloat(rows.count) * Self.rowHeight + 78)
        return NSSize(width: width, height: height)
    }

    private func makeToolbar() -> NSView {
        // A paired plus and minus under a list is the standard macOS control for
        // adding and removing, so rows and columns each get one.
        let rowControl = addRemoveControl(#selector(rowControlChanged), "row")
        let columnControl = addRemoveControl(#selector(columnControlChanged), "column")

        alignmentControl.segmentCount = 3
        alignmentControl.segmentStyle = .rounded
        alignmentControl.trackingMode = .selectOne
        alignmentControl.controlSize = .regular
        for (index, name) in ["text.alignleft", "text.aligncenter", "text.alignright"].enumerated() {
            alignmentControl.setImage(
                NSImage(systemSymbolName: name, accessibilityDescription: nil), forSegment: index)
            alignmentControl.setWidth(32, forSegment: index)
        }
        alignmentControl.target = self
        alignmentControl.action = #selector(alignmentChanged)

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 6
        // Gravity areas rather than a spacer view: the stack itself holds the
        // ends apart, which is what it is for.
        bar.addView(label("Rows"), in: .leading)
        bar.addView(rowControl, in: .leading)
        bar.addView(label("Columns"), in: .leading)
        bar.addView(columnControl, in: .leading)
        bar.addView(alignmentControl, in: .trailing)
        bar.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return bar
    }

    private func addRemoveControl(_ action: Selector, _ noun: String) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        control.segmentCount = 2
        control.segmentStyle = .rounded
        control.trackingMode = .momentary
        for (index, name) in ["plus", "minus"].enumerated() {
            control.setImage(
                NSImage(systemSymbolName: name, accessibilityDescription: nil), forSegment: index)
            control.setWidth(30, forSegment: index)
        }
        control.setToolTip("Add \(noun)", forSegment: 0)
        control.setToolTip("Remove \(noun)", forSegment: 1)
        control.target = self
        control.action = action
        return control
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        return field
    }

    @objc private func rowControlChanged(_ sender: NSSegmentedControl) {
        sender.selectedSegment == 0 ? addRow(sender) : removeRow(sender)
    }

    @objc private func columnControlChanged(_ sender: NSSegmentedControl) {
        sender.selectedSegment == 0 ? addColumn(sender) : removeColumn(sender)
    }

    private func rebuildColumns() {
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        for index in alignments.indices {
            let column = NSTableColumn(identifier: .init("column\(index)"))
            column.minWidth = 60
            column.maxWidth = 400
            // Start each column near the width of what is in it, so nothing is
            // truncated on opening that did not have to be.
            let longest = rows.map { index < $0.count ? $0[index].count : 0 }.max() ?? 0
            column.width = min(260, max(80, CGFloat(longest) * 7.5 + 18))
            tableView.addTableColumn(column)
        }
    }

    // MARK: - Editing

    private func commit() {
        onChange(TableFormatter.render(rows: rows, alignments: alignments))
    }

    @objc func addRow(_ sender: Any?) {
        let target = tableView.selectedRow >= 0 ? tableView.selectedRow + 1 : rows.count
        rows.insert(Array(repeating: "", count: alignments.count), at: target)
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
        commit()
        tableView.editColumn(0, row: target, with: nil, select: true)
    }

    @objc func removeRow(_ sender: Any?) {
        // The header is what names the columns, so it is not a row you can drop.
        let target = tableView.selectedRow
        guard target > 0, rows.count > 2 else { NSSound.beep(); return }
        rows.remove(at: target)
        tableView.reloadData()
        tableView.selectRowIndexes(
            IndexSet(integer: min(target, rows.count - 1)), byExtendingSelection: false)
        commit()
    }

    @objc func addColumn(_ sender: Any?) {
        let target = min(focusedColumn + 1, alignments.count)
        for index in rows.indices { rows[index].insert("", at: target) }
        alignments.insert(.none, at: target)
        // The new column is the one being worked on, so the alignment buttons
        // and a following Remove both act on it rather than on its neighbour.
        focusedColumn = target
        rebuildColumns()
        tableView.reloadData()
        commit()
        preferredContentSize = preferredSize
        tableView.editColumn(target, row: 0, with: nil, select: true)
    }

    @objc func removeColumn(_ sender: Any?) {
        guard alignments.count > 1 else { NSSound.beep(); return }
        let target = min(focusedColumn, alignments.count - 1)
        for index in rows.indices where rows[index].count > target {
            rows[index].remove(at: target)
        }
        alignments.remove(at: target)
        focusedColumn = min(focusedColumn, alignments.count - 1)
        rebuildColumns()
        tableView.reloadData()
        commit()
        preferredContentSize = preferredSize
        updateAlignmentControl()
    }

    @objc private func alignmentChanged(_ sender: NSSegmentedControl) {
        guard focusedColumn < alignments.count else { return }
        switch sender.selectedSegment {
        case 0: alignments[focusedColumn] = .left
        case 1: alignments[focusedColumn] = .center
        default: alignments[focusedColumn] = .right
        }
        commit()
    }

    private func updateAlignmentControl() {
        guard focusedColumn < alignments.count else { return }
        switch alignments[focusedColumn] {
        case .left: alignmentControl.selectedSegment = 0
        case .center: alignmentControl.selectedSegment = 1
        case .right: alignmentControl.selectedSegment = 2
        case .none: alignmentControl.selectedSegment = -1
        }
    }

    /// Selects a row without going through the view, for the self test.
    func selectRowForTesting(_ row: Int) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    /// Moves the field editor one cell on, wrapping to the next row and adding
    /// one when it runs off the end, which is how a table is filled in.
    private func edit(column: Int, row: Int) {
        var column = column
        var row = row
        if column >= alignments.count {
            column = 0
            row += 1
        }
        if column < 0 {
            column = alignments.count - 1
            row -= 1
        }
        guard row >= 0 else { return }
        if row >= rows.count {
            rows.append(Array(repeating: "", count: alignments.count))
            tableView.reloadData()
            commit()
        }
        tableView.editColumn(column, row: row, with: nil, select: true)
    }
}

// MARK: - Data

extension TableEditorViewController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(
        _ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int
    ) -> NSView? {
        guard let tableColumn,
              let column = tableView.tableColumns.firstIndex(of: tableColumn) else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("cell")
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            field = reused
        } else {
            field = NSTextField()
            field.identifier = identifier
            field.isBordered = false
            field.drawsBackground = false
            field.focusRingType = .none
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
        }
        field.isEditable = true
        field.tag = row * 1000 + column
        field.stringValue = row < rows.count && column < rows[row].count ? rows[row][column] : ""
        // The Markdown header row names the columns, so it reads as a heading.
        field.font = row == 0
            ? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.alignment = alignment(for: column)
        return field
    }

    private func alignment(for column: Int) -> NSTextAlignment {
        guard column < alignments.count else { return .natural }
        switch alignments[column] {
        case .right: return .right
        case .center: return .center
        case .left, .none: return .natural
        }
    }
}

// MARK: - Cell editing

extension TableEditorViewController: NSTextFieldDelegate {

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let row = field.tag / 1000
        let column = field.tag % 1000
        guard row < rows.count, column < rows[row].count else { return }

        focusedColumn = column
        updateAlignmentControl()

        // A newline inside a cell would end the row, and a pipe would split it.
        // Both are written out rather than refused, so a paste keeps its text.
        let cleaned = field.stringValue
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: #"\|"#)
            .trimmingCharacters(in: .whitespaces)
        guard rows[row][column] != cleaned else { return }
        rows[row][column] = cleaned
        commit()
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
        guard let field = control as? NSTextField else { return false }
        let row = field.tag / 1000
        let column = field.tag % 1000

        switch selector {
        case #selector(NSResponder.insertTab(_:)):
            field.window?.makeFirstResponder(tableView)
            edit(column: column + 1, row: row)
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            field.window?.makeFirstResponder(tableView)
            edit(column: column - 1, row: row)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            field.window?.makeFirstResponder(tableView)
            edit(column: column, row: row + 1)
            return true
        default:
            return false
        }
    }
}

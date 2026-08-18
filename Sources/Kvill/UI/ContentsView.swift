import AppKit

/// The current document's headings, down the side, for moving around a long one.
///
/// A flat table indented by depth rather than a real outline. Headings are
/// already a hierarchy in the text and collapsing them here would hide the very
/// rows someone opened this to find.
final class ContentsView: NSView {

    /// Called when a heading is chosen.
    var onJump: ((Outline.Entry) -> Void)?

    private let table = NSTableView()
    private let scrollView = NSScrollView()
    private let heading = NSTextField(labelWithString: "In this document")
    private(set) var entries: [Outline.Entry] = []
    /// Set while the selection is being moved to follow the caret, so following
    /// the caret does not read as a click and scroll the page out from under it.
    private var isSyncing = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func build() {
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        // After the style, not before it. Setting the style puts the selection
        // highlight back, so disabling it first disabled nothing and the current
        // heading kept a blue capsule in the middle of a page.
        table.selectionHighlightStyle = .none
        table.backgroundColor = .clear
        table.rowHeight = 22
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        // The tree learned this one: a scroll view adds insets of its own accord
        // and pushes its contents out of line with the label above it.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero

        addSubview(heading)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: leadingAnchor),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            heading.topAnchor.constraint(equalTo: topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        heading.textColor = ThemeManager.shared.theme.colors.textSecondary
        table.reloadData()
    }

    /// Replaces the list. Keeps the selection where it was if that heading is
    /// still there, so typing under a heading does not make the sidebar jump.
    func show(_ found: [Outline.Entry]) {
        guard found != entries else { return }
        let selectedTitle = table.selectedRow >= 0 && table.selectedRow < entries.count
            ? entries[table.selectedRow].title : nil
        entries = found
        table.reloadData()
        if let selectedTitle, let row = found.firstIndex(where: { $0.title == selectedTitle }) {
            isSyncing = true
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isSyncing = false
        }
    }

    /// Lights the heading the caret is under.
    func select(at location: Int) {
        guard let entry = Outline.entry(at: location, in: entries),
              let row = entries.firstIndex(of: entry) else {
            isSyncing = true
            table.deselectAll(nil)
            isSyncing = false
            return
        }
        guard table.selectedRow != row else { return }
        isSyncing = true
        let previous = table.selectedRow
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        // The current row is drawn in ink rather than highlighted, so both the
        // row being left and the row being entered have to be redrawn.
        for changed in [previous, row] where changed >= 0 && changed < entries.count {
            table.reloadData(forRowIndexes: IndexSet(integer: changed),
                             columnIndexes: IndexSet(integer: 0))
        }
        table.scrollRowToVisible(row)
        isSyncing = false
    }

    @objc private func rowClicked() {
        guard !isSyncing, table.clickedRow >= 0, table.clickedRow < entries.count else { return }
        onJump?(entries[table.clickedRow])
    }

    /// What the checks read instead of counting pixels.
    var titlesForTest: [String] { entries.map(\.title) }
    var selectedRowForTest: Int { table.selectedRow }
}

extension ContentsView: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView? {
        let entry = entries[row]
        let colors = ThemeManager.shared.theme.colors
        let label = NSTextField(labelWithString: entry.title)
        label.lineBreakMode = .byTruncatingTail
        // Top level reads as a heading, the rest as its contents.
        // The section the caret is in is the one in full ink. Everything else
        // is quiet, so the list reads as a margin note rather than a control.
        let current = row == table.selectedRow
        label.font = .systemFont(ofSize: 11.5, weight: current ? .semibold : .regular)
        label.textColor = current ? colors.accent : colors.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false

        let cell = NSTableCellView()
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(
                equalTo: cell.leadingAnchor, constant: CGFloat(entry.indent) * 12),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedRow()
    }

    /// How tall the list wants to be, so the page can give it exactly that and
    /// no scroll bar appears unless the document really is longer than the
    /// window.
    var wantedHeight: CGFloat {
        heading.intrinsicContentSize.height + 6
            + CGFloat(entries.count) * (table.rowHeight + table.intercellSpacing.height)
    }
}

/// A row that draws nothing of its own.
///
/// The heading the caret is under is shown by setting it in the accent colour,
/// not by putting a highlight behind it. This is a margin note beside a page,
/// and a selected row in the middle of a page reads as a control.
private final class ThemedRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}
    override func drawBackground(in dirtyRect: NSRect) {}
}

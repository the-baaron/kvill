import AppKit

/// The Markdown files in an opened folder, as a tree.
///
/// Only Markdown is listed. Everything else in the folder is still *readable*,
/// which is the other half of why this exists: the sandbox grants a folder
/// recursively, so opening one is what makes the images a document refers to
/// load at all. The tree is what you see; the access is what you get.
final class FileTreeView: NSView {

    /// Whether a URL is one of the documents this tree lists.
    static func isMarkdown(_ url: URL) -> Bool {
        Node.readable.contains(url.pathExtension.lowercased())
    }

    /// Called when a file is chosen.
    var onOpen: ((URL) -> Void)?

    private let outline = NSOutlineView()
    private let scrollView = NSScrollView()
    private var root: Node?

    /// A folder or a Markdown file. Folders holding no Markdown are left out,
    /// so the tree shows the documents rather than the disk.
    fileprivate final class Node {
        let url: URL
        let isFolder: Bool
        private(set) lazy var children: [Node] = isFolder ? Node.scan(url) : []

        init(url: URL, isFolder: Bool) {
            self.url = url
            self.isFolder = isFolder
        }

        var name: String { url.lastPathComponent }

        /// Markdown only. Kvill will open any text file handed to it, but the
        /// tree is for finding documents, and a folder of source code listed in
        /// full would bury them.
        static let readable: Set<String> = [
            "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtext", "qmd", "rmd",
        ]

        static func scan(_ folder: URL) -> [Node] {
            let keys: [URLResourceKey] = [.isDirectoryKey]
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }

            var found: [Node] = []
            for url in entries {
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                    .isDirectory ?? false
                if isFolder {
                    let node = Node(url: url, isFolder: true)
                    // A folder earns its place by containing something.
                    if !node.children.isEmpty { found.append(node) }
                } else if readable.contains(url.pathExtension.lowercased()) {
                    found.append(Node(url: url, isFolder: false))
                }
            }
            return found.sorted {
                $0.isFolder == $1.isFolder
                    ? $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    : $0.isFolder
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowSizeStyle = .default
        outline.style = .sourceList
        outline.backgroundColor = .clear
        outline.dataSource = self
        outline.delegate = self
        outline.target = self
        outline.action = #selector(clicked)
        outline.indentationPerLevel = 12

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: .kvillThemeChanged, object: nil)

        scrollView.documentView = outline
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 44),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// The sidebar is set in the page's own ink rather than the system's, so it
    /// belongs to the theme the way everything else in the window does.
    @objc private func themeChanged() { outline.reloadData() }

    /// Shows a folder. Access is opened first: without it the scan comes back
    /// empty and the tree would look like an empty folder rather than a refusal.
    func show(_ folder: URL) {
        guard FolderAccess.beginAccess(to: folder) else { return }
        root = Node(url: folder, isFolder: true)
        outline.reloadData()
        outline.expandItem(nil, expandChildren: false)
        for node in root?.children ?? [] where node.isFolder {
            outline.expandItem(node)
        }
    }

    /// Marks the file currently being edited, so the tree says where you are.
    func select(_ url: URL?) {
        guard let url, let root else { return }
        let target = url.standardizedFileURL
        for row in 0..<outline.numberOfRows {
            guard let node = outline.item(atRow: row) as? Node,
                  node.url.standardizedFileURL == target else { continue }
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            return
        }
        _ = root
    }

    /// How many rows the outline is actually showing, for the self test.
    var rowCountForTest: Int { outline.numberOfRows }

    /// Builds the row views up front. An outline view makes them lazily during a
    /// display pass, which an off-screen window never runs, so without this there
    /// is nothing to draw.
    func prepareForRender() {
        outline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 400)
        outline.tile()
        for row in 0..<outline.numberOfRows {
            _ = outline.rowView(atRow: row, makeIfNecessary: true)
            outline.view(atColumn: 0, row: row, makeIfNecessary: true)?
                .layoutSubtreeIfNeeded()
        }
        layoutSubtreeIfNeeded()
    }

    /// Every name the tree is showing, for the self test.
    var listedForTest: [String] {
        outline.reloadData()
        var names: [String] = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                names.append(node.url.deletingPathExtension().lastPathComponent)
                walk(node.children)
            }
        }
        walk(root?.children ?? [])
        return names
    }

    @objc private func clicked() {
        guard let node = outline.item(atRow: outline.clickedRow) as? Node else { return }
        if node.isFolder {
            if outline.isItemExpanded(node) { outline.collapseItem(node) }
            else { outline.expandItem(node) }
            return
        }
        onOpen?(node.url)
    }
}

// MARK: - Contents

extension FileTreeView: NSOutlineViewDataSource, NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? Node) ?? root)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (((item as? Node) ?? root)?.children[index]) as Any
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Node)?.isFolder ?? false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        guard let node = item as? Node else { return nil }

        let identifier = NSUserInterfaceItemIdentifier("row")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self)
            as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            image.contentTintColor = .secondaryLabelColor
            cell.addSubview(image)
            cell.imageView = image

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize + 1)
            label.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(label)
            cell.textField = label

            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 15),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        let ink = ThemeManager.shared.theme.colors.text
        cell.imageView?.contentTintColor = ink.withAlpha(0.45)
        cell.textField?.textColor = ink.withAlpha(0.8)
        cell.imageView?.image = NSImage(
            systemSymbolName: node.isFolder ? "folder" : "doc.text",
            accessibilityDescription: nil)
        // The extension is noise when every file has the same one.
        cell.textField?.stringValue = node.isFolder
            ? node.name
            : node.url.deletingPathExtension().lastPathComponent
        return cell
    }
}

import AppKit

/// The sidebar, as a view controller, because that is what `NSSplitViewItem`
/// takes.
///
/// Two things live in it: the files in an opened folder, and the headings of the
/// document on screen. The headings are why the sidebar is worth having for a
/// single file at all, which is the answer to a long README being hard to move
/// around in.
///
/// The behaviour is all AppKit's: collapsing, the width limits, the divider, the
/// animation, running full height under the title bar so the traffic lights sit
/// over it the way they do in Finder. None of that is written here.
final class SidebarViewController: NSViewController {

    let tree = FileTreeView()
    let contents = ContentsView()

    /// Whether the folder half is showing. Off, the contents take the whole
    /// sidebar.
    var showsTree: Bool = false {
        didSet {
            guard showsTree != oldValue, isViewLoaded else { return }
            apply()
        }
    }

    private let divider = NSBox()
    private var treeHeight: NSLayoutConstraint?
    private var contentsAtTop: NSLayoutConstraint?
    private var contentsUnderTree: NSLayoutConstraint?

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        divider.boxType = .separator
        for child in [tree, divider, contents] as [NSView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
        }

        // Clear of the traffic lights, which sit over a full-height sidebar
        // exactly as they do in Finder.
        let top = WindowDragArea.height
        // The files take the upper part and the headings the rest, so a long
        // document cannot push the file list off the bottom.
        treeHeight = tree.heightAnchor.constraint(
            equalTo: container.heightAnchor, multiplier: 0.45)
        contentsAtTop = contents.topAnchor.constraint(
            equalTo: container.topAnchor, constant: top)
        contentsUnderTree = contents.topAnchor.constraint(
            equalTo: divider.bottomAnchor, constant: 14)

        NSLayoutConstraint.activate([
            tree.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tree.topAnchor.constraint(equalTo: container.topAnchor, constant: top),

            divider.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            divider.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            divider.topAnchor.constraint(equalTo: tree.bottomAnchor, constant: 8),

            contents.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contents.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contents.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
        ])
        apply()

        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    private func apply() {
        tree.isHidden = !showsTree
        divider.isHidden = !showsTree
        treeHeight?.isActive = showsTree
        contentsUnderTree?.isActive = showsTree
        contentsAtTop?.isActive = !showsTree
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        // Slightly raised off the page, so the divider is not the only thing
        // telling the two apart.
        view.layer?.backgroundColor = ThemeManager.shared.theme.colors.backgroundElevated.cgColor
    }
}

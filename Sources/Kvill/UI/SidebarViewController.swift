import AppKit

/// The folder sidebar, as a view controller, because that is what
/// `NSSplitViewItem` takes.
///
/// The behaviour is all AppKit's: collapsing, the width limits, the divider, the
/// animation, running full height under the title bar so the traffic lights sit
/// over it the way they do in Finder. None of that is written here.
///
/// The colour is the palette's rather than the system's grey sidebar material.
/// Kvill's palettes are opaque paper colours, and a grey slab beside a sepia
/// page reads as two apps in one window.
final class SidebarViewController: NSViewController {

    let tree = FileTreeView()

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        tree.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tree)

        NSLayoutConstraint.activate([
            tree.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            // Clear of the traffic lights, which sit over a full-height sidebar
            // exactly as they do in Finder.
            tree.topAnchor.constraint(equalTo: container.topAnchor, constant: WindowDragArea.height),
            tree.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func applyTheme() {
        // Slightly raised off the page, so the divider is not the only thing
        // telling the two apart.
        view.layer?.backgroundColor = ThemeManager.shared.theme.colors.backgroundElevated.cgColor
    }
}

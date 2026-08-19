import AppKit

/// The folder sidebar, as a view controller, because that is what
/// `NSSplitViewItem` takes.
///
/// Only the files. The document's own headings were briefly in here too and did
/// not belong: the sidebar is about which file you are looking at, and an index
/// is about where you are inside one. That is a floating panel over the page
/// now, the way documentation sites do it.
///
/// The behaviour is all AppKit's: collapsing, the width limits, the divider, the
/// animation, running full height under the title bar so the traffic lights sit
/// over it the way they do in Finder. None of that is written here.
final class SidebarViewController: NSViewController {

    let tree = FileTreeView()

    /// How far the list sits below the top of the sidebar, so the traffic
    /// lights have somewhere to be. Kept, because in full screen they are not
    /// there and the room they need is 44 points of nothing at the top of the
    /// list.
    private var listTop: NSLayoutConstraint!

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        tree.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tree)

        // Clear of the traffic lights, which sit over a full-height sidebar
        // exactly as they do in Finder.
        listTop = tree.topAnchor.constraint(
            equalTo: container.topAnchor, constant: Self.roomForTrafficLights)

        NSLayoutConstraint.activate([
            tree.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            // Clear of the traffic lights, which sit over a full-height sidebar
            // exactly as they do in Finder.
            listTop,
            tree.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// The room the traffic lights need at the top of the sidebar.
    static let roomForTrafficLights = WindowDragArea.height

    /// The height of a plain title bar, which in full screen is exactly the
    /// strip that slides down when the pointer reaches the top edge. Asked for
    /// rather than written down: it measures 32 on this machine and that is not
    /// a number to hard code.
    static let revealedStrip = NSWindow.frameRect(
        forContentRect: .zero, styleMask: [.titled]).height

    /// What that room should be for a given window.
    ///
    /// Less in full screen, and for a different reason. Windowed, the room is
    /// for the traffic lights, which sit over the sidebar the way they do in
    /// Finder. In full screen they are not there, so 44 points would be a long
    /// empty column above the first file, and none at all puts the folder's
    /// name against the top edge of the screen and under the strip whenever it
    /// slides down. The strip's own height is the answer to both.
    static func listTop(inFullScreen: Bool) -> CGFloat {
        inFullScreen ? revealedStrip : roomForTrafficLights
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let wanted = Self.listTop(
            inFullScreen: view.window?.styleMask.contains(.fullScreen) ?? false)
        // Only when it differs, so this settles after one further pass rather
        // than asking a window that is laying out to lay out for ever.
        if listTop.constant != wanted { listTop.constant = wanted }
    }

    @objc private func applyTheme() {
        // Slightly raised off the page, so the divider is not the only thing
        // telling the two apart.
        view.layer?.backgroundColor = ThemeManager.shared.theme.colors.backgroundElevated.cgColor
    }
}

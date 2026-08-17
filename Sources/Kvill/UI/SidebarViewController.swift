import AppKit

/// The folder sidebar, as a view controller, because that is what
/// `NSSplitViewItem` takes.
///
/// The behaviour is all AppKit's: collapsing, the width limits, the divider, the
/// animation, running full height under the title bar so the traffic lights sit
/// over it the way they do in Finder. None of that is written here.
///
/// The *colour* is not AppKit's, and that is deliberate. A sidebar built with
/// `NSSplitViewItem(sidebarWithViewController:)` paints the system's grey
/// material, which is right in Finder and wrong here: next to an Onyx page it
/// read as a grey slab bolted to a black window, with the window's own clear
/// background showing through at the corners. Kvill has eight palettes and the
/// sidebar belongs to whichever one is on, so it paints the same backdrop and
/// tint the page does.
final class SidebarViewController: NSViewController {

    let tree = FileTreeView()

    /// Blur behind a translucent palette, off for the opaque ones.
    private let backdrop = NSVisualEffectView()
    /// The palette's own colour over the blur, so glass still reads as Frost or
    /// Onyx rather than as bare system blur.
    private let tint = NSView()

    private var theme: Theme { ThemeManager.shared.theme }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        backdrop.blendingMode = .behindWindow
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)

        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tint)

        tree.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tree)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),

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
        let colors = theme.colors
        let glass = colors.isTranslucent

        backdrop.isHidden = !glass
        // A hidden visual effect view keeps blurring unless told to stop.
        backdrop.state = glass ? .active : .inactive
        backdrop.material = colors.material
        backdrop.appearance = colors.appearance

        tint.isHidden = !glass
        tint.layer?.backgroundColor = glass
            ? colors.background.withAlphaComponent(colors.pageAlpha).cgColor
            : nil

        // Opaque palettes paint the sidebar directly. Slightly raised off the
        // page so the divider is not the only thing telling them apart.
        view.layer?.backgroundColor = glass ? nil : colors.backgroundElevated.cgColor
    }
}

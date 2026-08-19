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

    /// Whether the sidebar paints an opaque surface of its own, for the checks.
    ///
    /// If this ever goes back to nothing, macOS 26's own sidebar container shows
    /// through to what is behind the *window* and the column takes the colour of
    /// the desktop.
    var paintsItsOwnSurfaceForTest: Bool {
        guard let colour = view.layer?.backgroundColor else { return false }
        return colour.alpha > 0.99
    }

    /// Whether the panel is rounded and casts a shadow, for the checks.
    ///
    /// Both were the glass effect's, and painting over the effect took them with
    /// it: the column went square-edged and flat against the page, and the only
    /// way that showed up was a photograph. Measured after: the page reads
    /// 0.9804 and the pixels just right of the sidebar's edge read 0.9412 rising
    /// to 0.9647 over 12 points.
    var drawsItsOwnPanelForTest: Bool {
        guard let layer = view.layer else { return false }
        return layer.cornerRadius > 0 && layer.shadowOpacity > 0 && !layer.masksToBounds
    }

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
        let full = view.window?.styleMask.contains(.fullScreen) ?? false
        // Only when they differ, so this settles after one further pass rather
        // than asking a window that is laying out to lay out for ever.
        let list = Self.listTop(inFullScreen: full)
        if listTop.constant != list { listTop.constant = list }
    }

    @objc private func applyTheme() {
        // The theme's raised colour, so the column reads as a surface above the
        // page rather than a piece of it. Painted on this view itself: AppKit
        // rounds and clips the sidebar's own view and casts its shadow, so the
        // panel shape and the shadow stay the system's and only the colour is
        // this app's.
        //
        // Opaque on purpose. macOS 26 puts every sidebar inside an
        // `NSContainerConcentricGlassEffectView`, which samples what is behind
        // the *window*: with nothing painted here the column came out the colour
        // of the desktop while the floating buttons, which are glass inside the
        // window, stayed the colour of the page. Making it the buttons' glass
        // instead fixed the colour and not the behaviour, since a glass inside a
        // glass still follows the container's key state, so the sidebar darkened
        // when the window lost focus while the buttons brightened.
        view.layer?.backgroundColor =
            ThemeManager.shared.theme.colors.backgroundElevated.cgColor

        // The rounded panel and its shadow were the glass effect's, and painting
        // over the effect took both away with it. Drawn here instead, matching
        // what the system was drawing: measured off a photograph of the real
        // window, the corner's curve ran 15 points down from the panel's top
        // edge, which is a 10 point radius on a continuous curve.
        view.layer?.cornerRadius = Self.cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = false
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.12
        view.layer?.shadowRadius = 10
        view.layer?.shadowOffset = .zero
    }

    /// The radius of the sidebar's panel.
    static let cornerRadius: CGFloat = 10



}

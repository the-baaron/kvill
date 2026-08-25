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

    /// The panel the sidebar is drawn as.
    ///
    /// Its own view rather than the controller's, so its top edge can move
    /// without moving the list inside it. Windowed it fills the sidebar and
    /// nothing shows behind it. In full screen AppKit puts the sidebar hard
    /// against the top of the screen, and the panel starts where the floating
    /// buttons start instead, so the column has a top edge rather than running
    /// off the display.
    private let panel = NSView()

    /// Where the panel's top edge is, which is not where the list's is.
    private var panelTop: NSLayoutConstraint!

    /// How far the list sits below the top of the sidebar, so the traffic
    /// lights have somewhere to be. Kept, because in full screen they are not
    /// there and the room they need is 44 points of nothing at the top of the
    /// list.
    private var listTop: NSLayoutConstraint!

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        panel.wantsLayer = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(panel)
        panelTop = panel.topAnchor.constraint(equalTo: container.topAnchor)

        tree.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tree)


        // Clear of the traffic lights, which sit over a full-height sidebar
        // exactly as they do in Finder.
        listTop = tree.topAnchor.constraint(
            equalTo: container.topAnchor, constant: Self.roomForTrafficLights)

        NSLayoutConstraint.activate([
            panelTop,
            panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            panel.bottomAnchor.constraint(equalTo: container.bottomAnchor),

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

        // Where the panel starts depends on whether the window is in full
        // screen, and a layout pass is not guaranteed to happen after that
        // changes. A window restored straight into full screen at launch laid
        // the sidebar out before the style mask said `.fullScreen`, so the panel
        // kept the windowed value and ran off the top of the display, while the
        // same window toggled into full screen by hand came out right. Asked for
        // again on the transitions themselves, so the order does not matter.
        for name: NSNotification.Name in [
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(chromeChanged), name: name, object: nil)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// The window entered or left full screen, so the panel's top has moved.
    @objc private func chromeChanged(_ note: Notification) {
        guard note.object as? NSWindow === view.window else { return }
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    /// Whether the sidebar paints an opaque surface of its own, for the checks.
    ///
    /// If this ever goes back to nothing, macOS 26's own sidebar container shows
    /// through to what is behind the *window* and the column takes the colour of
    /// the desktop.
    var paintsItsOwnSurfaceForTest: Bool {
        guard let ground = view.layer?.backgroundColor,
              let surface = panel.layer?.backgroundColor else { return false }
        return ground.alpha > 0.99 && surface.alpha > 0.99
    }

    /// Whether the panel is rounded and casts a shadow, for the checks.
    ///
    /// Both were the glass effect's, and painting over the effect took them with
    /// it: the column went square-edged and flat against the page, and the only
    /// way that showed up was a photograph. Measured after: the page reads
    /// 0.9804 and the pixels just right of the sidebar's edge read 0.9412 rising
    /// to 0.9647 over 12 points.
    var drawsItsOwnPanelForTest: Bool {
        guard let layer = panel.layer else { return false }
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
        let top = Self.panelTop(inFullScreen: full)
        if panelTop.constant != top { panelTop.constant = top }
    }

    /// Where the panel's top edge sits.
    ///
    /// Windowed, at the very top: the sidebar runs full height under the title
    /// bar and the traffic lights sit over it, the way they do in Finder. In
    /// full screen there is no title bar and AppKit puts the sidebar against the
    /// top of the display, so the panel lines up with the floating buttons and
    /// the column reads as a panel again rather than as the edge of the screen.
    /// Always flush with the container it is in.
    ///
    /// The panel used to be inset in full screen so it would not run to the top
    /// of the display, and that was the wrong lever: the container AppKit draws
    /// around it, and the shadow that comes with it, stayed full height, so the
    /// shape moved and the shadow did not. The container is inset instead, by
    /// `DocumentSplitViewController` turning full height layout off in full
    /// screen, and then panel and shadow arrive together.
    static func panelTop(inFullScreen: Bool) -> CGFloat { 0 }

    @objc private func applyTheme() {
        // The theme's raised colour, so the column reads as a surface above the
        // page rather than a piece of it.
        //
        // Opaque on purpose. macOS 26 puts every sidebar inside an
        // `NSContainerConcentricGlassEffectView`, which samples what is behind
        // the *window*: with nothing painted here the column came out the colour
        // of the desktop while the floating buttons, which are glass inside the
        // window, stayed the colour of the page. Making it the buttons' glass
        // instead fixed the colour and not the behaviour, since a glass inside a
        // glass still follows the container's key state, so the sidebar darkened
        // when the window lost focus while the buttons brightened.
        let colors = ThemeManager.shared.theme.colors
        // The ground the panel sits on, so that where the panel does not reach
        // the column reads as page rather than as whatever is behind the window.
        view.layer?.backgroundColor = colors.background.cgColor

        panel.layer?.backgroundColor = colors.backgroundElevated.cgColor

        // The rounded panel and its shadow were the glass effect's, and painting
        // over the effect took both away with it. Drawn here instead, matching
        // what the system was drawing: measured off a photograph of the real
        // window, the corner's curve ran 15 points down from the panel's top
        // edge, which is a 10 point radius on a continuous curve.
        panel.layer?.cornerRadius = Self.cornerRadius
        panel.layer?.cornerCurve = .continuous
        panel.layer?.masksToBounds = false
        panel.layer?.shadowColor = NSColor.black.cgColor
        panel.layer?.shadowOpacity = 0.12
        panel.layer?.shadowRadius = 10
        panel.layer?.shadowOffset = .zero
    }

    /// The radius of the sidebar's panel.
    static let cornerRadius: CGFloat = 10



}

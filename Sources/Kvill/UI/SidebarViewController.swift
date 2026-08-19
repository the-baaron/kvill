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

    /// The sidebar's own surface: opaque, and painted rather than sampled.
    ///
    /// This is deliberately not glass, and it took three attempts to be sure
    /// that was the right answer.
    ///
    /// macOS 26 puts every sidebar inside an
    /// `NSContainerConcentricGlassEffectView`, which samples what is behind the
    /// *window*. On a purple desktop the sidebar came out purple while the
    /// buttons a hundred points away stayed the colour of the page, because
    /// those are `NSGlassEffectView` inside the window and sample the page.
    ///
    /// Laying the buttons' own glass inside the sidebar fixed the colour and
    /// not the behaviour: a glass inside a glass still follows the container's
    /// key state, so the sidebar darkened when the window lost focus while the
    /// buttons brightened. Measured over the same 0.9804 ground, the panel
    /// rendered 0.9412 and the button 0.9922; Liquid Glass renders by size, and
    /// a 34 point capsule is nearly all edge lensing where a 180 point panel is
    /// nearly all body. There is no tint that makes one behave like the other.
    ///
    /// So the sidebar is painted. It covers the container entirely, so nothing
    /// reaches through to the desktop, and it looks the same whether the window
    /// is key or not, which is the thing that actually reads as wrong.
    private let backdrop = NSView()


    /// How far the list sits below the top of the sidebar, so the traffic
    /// lights have somewhere to be. Kept, because in full screen they are not
    /// there and the room they need is 44 points of nothing at the top of the
    /// list.
    private var listTop: NSLayoutConstraint!

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        // Something opaque for the glass to sit on. Without it the glass samples
        // AppKit's own sidebar container, which is a hole through to the
        // desktop, and the sidebar came out the colour of the wallpaper.
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = Self.cornerRadius
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.masksToBounds = true
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)

        tree.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tree)


        // Clear of the traffic lights, which sit over a full-height sidebar
        // exactly as they do in Finder.
        listTop = tree.topAnchor.constraint(
            equalTo: container.topAnchor, constant: Self.roomForTrafficLights)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),

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
    /// Not glass, on purpose: see `backdrop`. If this ever goes back to nothing,
    /// AppKit's own container shows through to the desktop and the sidebar takes
    /// the colour of the wallpaper.
    var paintsItsOwnSurfaceForTest: Bool {
        guard let colour = backdrop.layer?.backgroundColor else { return false }
        return colour.alpha > 0.99
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

    /// Measured off a photograph of the real window rather than guessed: the
    /// corner's curve runs 15 points down from the panel's top edge, which is a
    /// 10 point radius drawn as a continuous curve.
    static let cornerRadius: CGFloat = 10

    @objc private func applyTheme() {
        // The raised colour, so the column reads as a surface above the page
        // rather than a piece of it.
        backdrop.layer?.backgroundColor =
            ThemeManager.shared.theme.colors.backgroundElevated.cgColor
    }



}

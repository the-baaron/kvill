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

    /// The material the sidebar is made of, matching the floating buttons.
    ///
    /// macOS 26 puts every sidebar in an `NSContainerConcentricGlassEffectView`
    /// of its own, and that one samples what is behind the *window*: on a purple
    /// desktop the sidebar came out purple while the buttons a hundred points to
    /// its right stayed the colour of the page. They are two different glasses,
    /// and only one of them is reaching through the window.
    ///
    /// This is the buttons' glass, laid inside the sidebar so it samples the
    /// window's own content the way theirs does. One material, one colour.
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

        // The list goes inside the glass, not on top of it. An
        // `NSGlassEffectView` with no `contentView` draws nothing at all: the
        // first attempt at this measured a flat 0.9569 straight across 180
        // points, which is a plain fill showing through an inert view, while
        // the buttons vary from 0.984 to 0.992 across theirs. Same class, same
        // style, and the difference was that the buttons set `contentView` and
        // this did not.
        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        tree.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(tree)


        // Clear of the traffic lights, which sit over a full-height sidebar
        // exactly as they do in Finder.
        listTop = tree.topAnchor.constraint(
            equalTo: holder.topAnchor, constant: Self.roomForTrafficLights)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tree.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            // Clear of the traffic lights, which sit over a full-height sidebar
            // exactly as they do in Finder.
            listTop,
            tree.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])

        buildBackdrop(around: holder)
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Whether the list is inside the glass rather than sitting on top of it,
    /// for the checks.
    ///
    /// An `NSGlassEffectView` with no `contentView` draws nothing at all, and
    /// nothing looks exactly like a plain fill. The first version of this
    /// measured a flat 0.9569 straight across 180 points, which is what an
    /// inert glass over a solid colour reads as.
    var listIsInsideTheGlassForTest: Bool {
        guard #available(macOS 26.0, *) else { return true }
        var candidate: NSView? = tree
        while let current = candidate {
            if let glass = current.superview as? NSGlassEffectView {
                return glass.contentView != nil
            }
            candidate = current.superview
        }
        return false
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

    /// Builds the glass, once, into `backdrop`.
    private func buildBackdrop(around holder: NSView) {
        let material: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.style = .regular
            glass.contentView = holder
            material = glass
        } else {
            holder.translatesAutoresizingMaskIntoConstraints = false
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = Self.cornerRadius
            effect.layer?.cornerCurve = .continuous
            effect.layer?.masksToBounds = true
            effect.addSubview(holder)
            material = effect
        }
        material.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(material)
        NSLayoutConstraint.activate([
            material.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            material.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            material.topAnchor.constraint(equalTo: view.topAnchor),
            material.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            holder.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            holder.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            holder.topAnchor.constraint(equalTo: material.topAnchor),
            holder.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
    }

    /// Measured off a photograph of the real window rather than guessed: the
    /// corner's curve runs 15 points down from the panel's top edge, which is a
    /// 10 point radius drawn as a continuous curve.
    static let cornerRadius: CGFloat = 10

    @objc private func applyTheme() {
        // Page colour under the glass, and nothing else here.
        //
        // The glass above is `NSGlassEffectView` at `.regular`, the same view
        // the floating buttons are made of. It was still coming out the colour
        // of the desktop, because glass is translucent and what sits behind it
        // in a sidebar is AppKit's own container glass, which is a hole through
        // to the wallpaper. The buttons look the way they do because what is
        // behind *them* is the page. So the page's colour goes under this
        // glass, and then the two stacks are identical.
        backdrop.layer?.backgroundColor = ThemeManager.shared.theme.colors.page.cgColor
    }



}

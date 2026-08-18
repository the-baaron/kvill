import AppKit

/// A window per document, with a transparent title bar so the page runs edge to
/// edge. Window tabbing is disabled on purpose: opening a second file gives a
/// second window, never a tab.
final class DocumentWindowController: NSWindowController, NSWindowDelegate {

    /// Whether document windows are being built for the checks rather than for
    /// a person.
    ///
    /// Set for the length of `--selftest`. Someone is using this machine while
    /// the checks run, and hiding a window after AppKit has already put it on
    /// screen still flashes it in their face for a frame or two. Built hidden,
    /// so there is nothing to flash: off screen, transparent, and ignoring the
    /// mouse, but still a real window that reports itself visible, because some
    /// of what is being checked asks exactly that.
    static var buildsHidden = false

    static func create() -> DocumentWindowController {
        let split = DocumentSplitViewController(page: DocumentViewController())

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = split
        // Setting a content view controller resizes the window to that view's
        // fitting size. The editor has no intrinsic size, so restore the frame.
        window.setContentSize(NSSize(width: 900, height: 720))
        window.center()
        if buildsHidden {
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        }
        window.titlebarAppearsTransparent = true
        // Nothing draws a line across or down the title bar. With a translucent
        // palette there is no opaque ground under it, so a hairline reads as a
        // gap with the desktop behind it.
        window.titlebarSeparatorStyle = .none
        // The name is drawn in the page instead, centred and only at the top of
        // the document, so the title bar itself stays empty.
        window.titleVisibility = .hidden
        // The system's tabs, and the system's decision about them. `.automatic`
        // follows "Prefer tabs when opening documents" in System Settings, which
        // is off for most people, so a plain double-click still gets a window of
        // its own. Nothing here is drawn or maintained: the tab bar, the Window
        // menu items and the merge command are all AppKit's.
        window.tabbingMode = .automatic
        window.tabbingIdentifier = "design.baars.Kvill.document"
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("KvillDocument")
        // Opening a file should open that file and nothing else. Without this,
        // macOS restores the previous session's documents alongside it.
        window.isRestorable = false

        let controller = DocumentWindowController(window: window)
        controller.shouldCascadeWindows = true
        controller.start()

        // An empty toolbar, purely for the taller unified title bar it brings.
        // The traffic lights are laid out by the system against that height;
        // without it they sit hard against the top edge with the sidebar's first
        // row close underneath. It carries no items: the sidebar button floats
        // in the page so it can line up with the display options button on the
        // other side, which a toolbar item cannot.
        let toolbar = NSToolbar(identifier: "KvillToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        return controller
    }

    /// `windowDidLoad` is only called for a window that came from a nib. This
    /// one is built in code, so setup runs here instead: without it the window
    /// keeps its launch appearance and the traffic lights stay wrong after a
    /// switch to a dark theme.
    private func start() {
        // Set explicitly. An NSWindowController adopts the delegate only for a
        // window that came out of a nib, and this one is built in code, so
        // without this the full screen notifications never arrive.
        window?.delegate = self
        addSoftScrollEdge()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Asks the system for the soft scroll edge under the title bar.
    ///
    /// AppKit reaches `NSScrollEdgeEffectStyle` only through a titlebar
    /// accessory: there is no property on the scroll view. The accessory needs a
    /// real height, since the effect applies to content scrolling behind it, and
    /// an empty one produced nothing.
    ///
    /// There is no equivalent for the bottom of a window, so there is no bottom
    /// edge effect. Drawing one by hand cost several milliseconds a frame and
    /// never matched the system's.
    private func addSoftScrollEdge() {
        guard #available(macOS 26.1, *), let window else { return }

        let accessory = NSTitlebarAccessoryViewController()
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        host.wantsLayer = true
        accessory.view = host
        // Kept, so a palette change can repaint it. In full screen the title bar
        // is a strip of its own above the content, and painting it the page's
        // colour is what stops a seam showing across the top.
        scrollEdgeHost = host
        accessory.layoutAttribute = .bottom
        accessory.automaticallyAdjustsSize = false
        // Nothing across the top in full screen. Without this AppKit keeps the
        // title bar as a strip of its own above the page, the width of the
        // display, and there is no colour that makes a strip belong there: with
        // the bar transparent it came out black, and opaque it came out as the
        // system's own material against a paper page. Zero means it hides
        // altogether and the page fills the screen, sliding down only when the
        // pointer goes looking for it.
        accessory.fullScreenMinHeight = 0
        accessory.preferredScrollEdgeEffectStyle = .soft
        window.addTitlebarAccessoryViewController(accessory)
    }

    /// The accessory's view, so the palette can reach it.
    private weak var scrollEdgeHost: NSView?

    /// Whether the system scroll edge effect was asked for.
    var hasSoftScrollEdge: Bool {
        guard #available(macOS 26.1, *), let window else { return false }
        return window.titlebarAccessoryViewControllers.contains {
            $0.preferredScrollEdgeEffectStyle == .soft
        }
    }


    /// In full screen the title bar is its own strip above the content, and a
    /// transparent one is painted by nothing at all.
    ///
    /// Windowed, the page runs up under a transparent title bar and the window's
    /// own background fills whatever the content does not, which is why nothing
    /// showed through there. Full screen puts the title bar in a separate window
    /// of its own, 102 points tall across the whole display, and that one has no
    /// background to inherit: it came out black above the page.
    ///
    /// Opaque for the length of full screen, so AppKit paints it with the
    /// window's colour, which is the palette's. Transparent again on the way
    /// out, because windowed is where the transparency earns its keep.
    /// Full screen puts the title bar in a strip of its own above the page,
    /// across the whole display, and there is no colour that makes a strip
    /// belong there.
    ///
    /// Transparent, nothing paints it and it comes out near black on a paper
    /// page. Opaque, AppKit paints it with the window's own material, which
    /// follows the palette's appearance and sits against the page instead of
    /// against the desktop. Both were tried and photographed; this is the one
    /// that does not put a dark band across the top.
    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.titlebarAppearsTransparent = false
        window?.titlebarSeparatorStyle = .none
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        // Windowed is where the transparency earns its keep: the page runs up
        // under the title bar and the window's own background fills the rest.
        window?.titlebarAppearsTransparent = true
    }

    /// Matches the window chrome to the document's palette so the title bar does
    /// not sit as a grey strip above a sepia page.
    @objc private func applyTheme() {
        let theme = ThemeManager.shared.theme
        window?.isOpaque = true
        window?.backgroundColor = theme.colors.background
        // The strip AppKit puts above the content in full screen takes this
        // colour, so a palette change has to reach it too.
        scrollEdgeHost?.layer?.backgroundColor = theme.colors.background.cgColor
        // Drives the traffic lights and the title text. Without an explicit
        // appearance they follow the system, so light buttons end up on a dark
        // page, or dark ones on Sepia.
        window?.appearance = theme.colors.appearance
        window?.invalidateShadow()
    }

    // MARK: - Full screen

    @objc func toggleFullScreenMode(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }
}

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
        // window that came out of a nib, and this one is built in code.
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
        // Empty, and not layer-backed. A layer-backed view here is a surface
        // with nothing in it, and in full screen, where the title bar is a
        // strip of its own with no material behind it, that surface composited
        // as the black band across the top. A plain view draws nothing at all.
        // Its height is asked for and ignored: AppKit gives the strip 36 points
        // whatever this says, measured from 0 up to 36.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        accessory.view = host
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

    /// Whether the system scroll edge effect was asked for.
    var hasSoftScrollEdge: Bool {
        guard #available(macOS 26.1, *), let window else { return false }
        return window.titlebarAccessoryViewControllers.contains {
            $0.preferredScrollEdgeEffectStyle == .soft
        }
    }


    /// Nothing across the top in full screen, until the pointer goes looking
    /// for it.
    ///
    /// The black band was the toolbar. This window carries an empty one purely
    /// for the taller title bar it brings, and AppKit keeps a toolbar on screen
    /// in full screen: a strip the width of the display, transparent because
    /// this window's title bar is, with no window background behind it to show
    /// through. Painted by nothing, it came out black, and the first heading
    /// was cut in half behind it.
    ///
    /// Two earlier attempts missed it, both reasoned about rather than
    /// photographed. Making the title bar opaque replaced a black strip with a
    /// grey one. Painting the scroll edge accessory the page colour put a
    /// second opaque band across the *windowed* title bar as well, over the
    /// sidebar's shadow and over anything scrolled under it.
    ///
    /// `.autoHideToolbar` is the system's own answer, the one every full screen
    /// app on the machine uses: the strip is gone and slides down when the
    /// pointer reaches the top edge. It is only legal alongside `.fullScreen`
    /// and `.autoHideMenuBar`, so all three go together.
    func window(
        _ window: NSWindow,
        willUseFullScreenPresentationOptions proposed: NSApplication.PresentationOptions
    ) -> NSApplication.PresentationOptions {
        proposed.union([.fullScreen, .autoHideMenuBar, .autoHideToolbar])
    }

    /// The strip that slides down when the pointer reaches the top edge is the
    /// system's, and it cannot be done away with: it is where the traffic
    /// lights and the menu bar live in full screen. It can be half the size,
    /// and it can be painted.
    ///
    /// Windowed, this app carries an empty toolbar for one reason: a plain
    /// title bar is 32 points and puts the traffic lights hard against the top
    /// edge with the sidebar's first row right underneath. A unified toolbar
    /// takes it to 66. Both measured on this machine. In full screen nothing
    /// sits under the strip to be crowded, so the toolbar has no work to do and
    /// the reveal is 32 points instead of 66.
    ///
    /// Opaque for the length of full screen as well, because a transparent
    /// title bar has a window background behind it only when there is a window:
    /// the full screen strip is its own, with nothing behind it, and painted by
    /// nothing it came out black.
    ///
    /// Both changes are made after the transition rather than during it. The
    /// earlier version did this in `willEnter` and `willExit`, which asks
    /// AppKit to rebuild the window's frame view in the middle of its own
    /// transform animation, and there is a crash report from that build with
    /// `-[_NSWindowTransformAnimation dealloc]` on the stack.
    func windowWillEnterFullScreen(_ notification: Notification) {
        // Before the transition rather than after it. Done afterwards, the
        // whole animation played with the strip unpainted, which is the black
        // band that flashes across the top on the way in.
        window?.titlebarAppearsTransparent = false
        // Taken away, not hidden, and before the transition rather than after
        // it. `toolbar.isVisible = false` does nothing, and removing the
        // toolbar once AppKit has already built the full screen strip does
        // nothing either: measured both ways, the strip stayed 68 points tall.
        // Removed before the transition, it is built without one.
        parkedToolbar = window?.toolbar
        window?.toolbar = nil
        // And the scroll edge strip with it. 32 points of title bar plus its
        // 36 is the 68 the reveal measures; `fullScreenMinHeight = 0` does not
        // keep it out of the strip, it only keeps it hidden until the strip
        // itself is revealed.
        parkedAccessories = window?.titlebarAccessoryViewControllers ?? []
        while (window?.titlebarAccessoryViewControllers.isEmpty == false) {
            window?.removeTitlebarAccessoryViewController(at: 0)
        }
        window?.titlebarSeparatorStyle = .none
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        window?.titlebarSeparatorStyle = .none
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // After the transition, not before it. Nothing is mutated while
        // AppKit's transform animation is running, which is where a crash
        // report from build 27 points.
        if let parkedToolbar {
            window?.toolbar = parkedToolbar
            window?.toolbarStyle = .unified
        }
        parkedToolbar = nil
        for accessory in parkedAccessories { window?.addTitlebarAccessoryViewController(accessory) }
        parkedAccessories = []
        window?.titlebarAppearsTransparent = true
        window?.titlebarSeparatorStyle = .none
    }

    /// The window's toolbar while full screen has it out of the way.
    private var parkedToolbar: NSToolbar?

    /// And its titlebar accessories, for the same reason.
    private var parkedAccessories: [NSTitlebarAccessoryViewController] = []

    /// Matches the window chrome to the document's palette so the title bar does
    /// not sit as a grey strip above a sepia page.
    @objc private func applyTheme() {
        let theme = ThemeManager.shared.theme
        window?.isOpaque = true
        window?.backgroundColor = theme.colors.background
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

import AppKit

/// A window per document, with a transparent title bar so the page runs edge to
/// edge. Window tabbing is disabled on purpose: opening a second file gives a
/// second window, never a tab.
final class DocumentWindowController: NSWindowController {

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
        window.titlebarAppearsTransparent = true
        // Nothing draws a line across or down the title bar. With a translucent
        // palette there is no opaque ground under it, so a hairline reads as a
        // gap with the desktop behind it.
        window.titlebarSeparatorStyle = .none
        // The name is drawn in the page instead, centred and only at the top of
        // the document, so the title bar itself stays empty.
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
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
        accessory.layoutAttribute = .bottom
        accessory.automaticallyAdjustsSize = false
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

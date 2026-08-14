import AppKit

/// A window per document, with a transparent title bar so the page runs edge to
/// edge. Window tabbing is disabled on purpose: opening a second file gives a
/// second window, never a tab.
final class DocumentWindowController: NSWindowController {

    static func create() -> DocumentWindowController {
        let viewController = DocumentViewController()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = viewController
        // Setting a content view controller resizes the window to that view's
        // fitting size. The editor has no intrinsic size, so restore the frame.
        window.setContentSize(NSSize(width: 900, height: 720))
        window.center()
        window.titlebarAppearsTransparent = true
        // The name is drawn in the page instead, centred and only at the top of
        // the document, so the title bar itself stays empty.
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("SignetDocument")
        // Opening a file should open that file and nothing else. Without this,
        // macOS restores the previous session's documents alongside it.
        window.isRestorable = false

        let controller = DocumentWindowController(window: window)
        controller.shouldCascadeWindows = true
        controller.start()
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
            self, selector: #selector(applyTheme), name: .signetThemeChanged, object: nil)
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
        // A translucent palette needs the window itself to be see-through,
        // otherwise the blur behind the page has nothing to blur.
        window?.isOpaque = !theme.colors.isTranslucent
        window?.backgroundColor = theme.colors.isTranslucent ? .clear : theme.colors.background
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

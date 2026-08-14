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
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 520, height: 420)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("QuillDocument")
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
            self, selector: #selector(applyTheme), name: .quillThemeChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Asks the system for the soft scroll edge under the title bar.
    ///
    /// In AppKit this is a property of a titlebar accessory, not of the scroll
    /// view: `NSTitlebarAccessoryViewController.preferredScrollEdgeEffectStyle`.
    /// There is no equivalent for the bottom of a window, which is drawn by hand.
    private func addSoftScrollEdge() {
        guard #available(macOS 26.1, *), let window else { return }

        let accessory = NSTitlebarAccessoryViewController()
        // An empty accessory: all that is wanted is the edge it brings with it.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
        host.translatesAutoresizingMaskIntoConstraints = true
        accessory.view = host
        accessory.layoutAttribute = .bottom
        accessory.automaticallyAdjustsSize = false
        accessory.preferredScrollEdgeEffectStyle = .soft
        window.addTitlebarAccessoryViewController(accessory)
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

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
        controller.applyTheme()
        return controller
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .quillThemeChanged, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Matches the window chrome to the document's palette so the title bar does
    /// not sit as a grey strip above a sepia page.
    @objc private func applyTheme() {
        let theme = ThemeManager.shared.theme
        window?.backgroundColor = theme.colors.background
        window?.appearance = theme.colors.appearance
    }

    // MARK: - Full screen

    @objc func toggleFullScreenMode(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }
}

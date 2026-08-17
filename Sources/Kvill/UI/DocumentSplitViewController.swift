import AppKit

/// The window's content: a sidebar and the page, held by AppKit rather than by
/// arithmetic in this app.
///
/// This replaces a hand-written sidebar that owned its width, its animation, its
/// collapsed state, a tracking strip for the hover reveal, and a rule about when
/// the page should move over for it. Every one of those is something
/// `NSSplitViewItem` already does, and doing them again produced a page that sid
/// towards the sidebar covering it, and very nearly an abort from changing a
/// constraint inside a layout pass.
///
/// What is left here is only the things AppKit cannot know: which folder to
/// show, and which document the page is showing.
final class DocumentSplitViewController: NSSplitViewController {

    let sidebar = SidebarViewController()
    private var sidebarItem: NSSplitViewItem!
    private var pageItem: NSSplitViewItem!

    /// The editor currently in the window. Swapped when the sidebar is used to
    /// switch files, which is why it is not a `let`.
    private(set) var page: DocumentViewController

    /// The folder the sidebar is showing, so a document arriving in this window
    /// can be given the same one.
    private(set) var folder: URL?

    init(page: DocumentViewController) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        applyTheme()
        NotificationCenter.default.addObserver(
            self, selector: #selector(applyTheme), name: .kvillThemeChanged, object: nil)

        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320
        sidebarItem.canCollapse = true
        // Nothing to show until a folder is opened.
        sidebarItem.isCollapsed = true
        // Remembered per window across launches, which is the standard
        // behaviour and one more thing not worth writing.
        sidebarItem.automaticMaximumThickness = 320
        // No separator lines. The window has a transparent title bar and, on a
        // translucent palette, no opaque ground for a hairline to sit on, so the
        // automatic one drew a seam with the desktop showing through beside it.
        sidebarItem.titlebarSeparatorStyle = .none
        addSplitViewItem(sidebarItem)

        pageItem = NSSplitViewItem(viewController: page)
        pageItem.canCollapse = false
        pageItem.minimumThickness = 380
        pageItem.titlebarSeparatorStyle = .none
        addSplitViewItem(pageItem)

        // No autosaveName. It restores a divider position from a previous run,
        // which quietly uncollapses a sidebar that is meant to start closed
        // until a folder is opened.
    }

    // MARK: - The folder

    /// Shows a folder's Markdown down the side and opens the sidebar for it.
    func showFolder(_ url: URL) {
        folder = url
        sidebar.tree.onOpen = { [weak self] file in
            self?.open(file)
        }
        sidebar.tree.show(url)
        sidebar.tree.select(page.documentURL)
        // A sidebar listing one file is a list of the thing you are already
        // looking at. Nothing to move between, so nothing to show, and the
        // button that opens it goes too.
        guard hasSomethingToSwitchBetween else {
            if !sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = true }
            return
        }
        if sidebarItem.isCollapsed {
            // Through the animator, so it slides the way every other sidebar on
            // the system does.
            sidebarItem.animator().isCollapsed = false
        }
    }

    /// Whether the open folder holds more than one file worth listing.
    var hasSomethingToSwitchBetween: Bool {
        guard folder != nil else { return false }
        return sidebar.tree.documentCount > 1
    }

    /// Called when a file is chosen in the sidebar.
    private func open(_ url: URL) {
        guard let window = view.window,
              let current = NSDocumentController.shared.document(for: window),
              let controller = NSDocumentController.shared as? KvillDocumentController,
              controller.openInPlace(url, replacing: current)
        else {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            return
        }
        sidebar.tree.select(url)
    }

    /// Puts a different document's editor in the window, keeping the sidebar.
    ///
    /// The editor is replaced rather than reused. A document reads its text out
    /// of its own editor when it saves, so two documents sharing one is how four
    /// of someone's notes ended up holding each other's contents.
    func showPage(_ next: DocumentViewController) {
        let wasCollapsed = sidebarItem.isCollapsed
        removeSplitViewItem(pageItem)
        page = next
        pageItem = NSSplitViewItem(viewController: next)
        pageItem.canCollapse = false
        pageItem.minimumThickness = 380
        addSplitViewItem(pageItem)
        sidebarItem.isCollapsed = wasCollapsed
        if let folder { sidebar.tree.show(folder) }
        sidebar.tree.select(next.documentURL)
    }

    /// Paints the ground the two panes sit on.
    ///
    /// macOS 26 draws a sidebar as a rounded panel inset from the window, and
    /// nothing was painting the gap that leaves, so on a translucent palette the
    /// window's clear background showed through as a black frame around it.
    ///
    /// Done on the split view's own layer rather than by putting a backdrop
    /// behind it. This controller's view *is* the `NSSplitView`; replacing it in
    /// `loadView` with a container of my own stopped the panes laying out
    /// altogether, and three checks caught it.
    @objc private func applyTheme() {
        let colors = ThemeManager.shared.theme.colors
        splitView.wantsLayer = true
        splitView.layer?.backgroundColor = colors.background.cgColor
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Whether the sidebar is showing, for the self test.
    var isShowingFileTree: Bool { sidebarItem != nil && !sidebarItem.isCollapsed }
}

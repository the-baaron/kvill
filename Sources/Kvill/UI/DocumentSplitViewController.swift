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

    /// The second document, when there is one.
    ///
    /// A pane, not a window: `NSSplitViewItem` already does the divider, the
    /// dragging, the minimum widths and the collapse, and every one of those is
    /// something a hand-written two-up view would have to do again.
    private(set) var companion: DocumentViewController?
    private var companionItem: NSSplitViewItem?

    /// Whether this window is showing two documents.
    var isSplit: Bool { companion != nil }

    /// The folder the sidebar is showing, so a document arriving in this window
    /// can be given the same one.
    private(set) var folder: URL?

    /// The page pane, built the same way wherever it is built.
    ///
    /// It used to be built twice, once here and once in `showPage`, and the
    /// second one was missing `titlebarSeparatorStyle`. So the window had no
    /// hairline under its title bar until you clicked a file in the sidebar,
    /// and then it did, for the rest of that window's life. In full screen that
    /// line is the border across the strip that slides down from the top.
    private static func makePageItem(_ page: DocumentViewController) -> NSSplitViewItem {
        let item = NSSplitViewItem(viewController: page)
        item.canCollapse = false
        item.minimumThickness = 380
        // No separator lines. The window has a transparent title bar and, on a
        // translucent palette, no opaque ground for a hairline to sit on, so the
        // automatic one drew a seam with the desktop showing through beside it.
        item.titlebarSeparatorStyle = .none
        return item
    }

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

        // Full height under the title bar in a window, so the traffic lights sit
        // over the sidebar the way they do in Finder. Not in full screen: there
        // is no title bar to run under, and full height there means the system's
        // own panel, and the shadow it draws, run to the very top of the display
        // while everything else in the app starts below it. Turning it off in
        // full screen insets the container itself, shadow included, which is the
        // one thing this app cannot do from the inside: measured, the container
        // goes from {{8, 8}, {180, 1076}} to {{8, 8}, {180, 1068}} in a 1084
        // point window, so 8 points down from the top rather than none.
        NotificationCenter.default.addObserver(
            self, selector: #selector(fullScreenChanged),
            name: NSWindow.willEnterFullScreenNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(fullScreenChanged),
            name: NSWindow.willExitFullScreenNotification, object: nil)
        addSplitViewItem(sidebarItem)

        pageItem = Self.makePageItem(page)
        addSplitViewItem(pageItem)

        // No autosaveName. It restores a divider position from a previous run,
        // which quietly uncollapses a sidebar that is meant to start closed
        // until a folder is opened.
    }

    /// Whether the sidebar runs under the title bar, which only a window has.
    /// Set on the way in and out, not afterwards.
    ///
    /// Changing it once the window is already in full screen does nothing: the
    /// container measured {{8, 8}, {180, 1076}} in a 1084 point window either
    /// way, which is flush with the top. Set before the transition it measures
    /// 1068, which is the 8 points down this is for.
    @objc private func fullScreenChanged(_ note: Notification) {
        guard note.object as? NSWindow === view.window else { return }
        let entering = note.name == NSWindow.willEnterFullScreenNotification
        setFullHeightLayout(!entering)
    }

    private func setFullHeightLayout(_ wanted: Bool) {
        guard sidebarItem.allowsFullHeightLayout != wanted else { return }
        sidebarItem.allowsFullHeightLayout = wanted
        // Laid out at once, not left to the transition. Setting the property
        // and waiting measured {{8, 8}, {180, 1076}} in a 1084 point window,
        // which is flush with the top; forcing the pass here measures 1068.
        splitView.adjustSubviews()
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // A window restored straight into full screen never sees a transition.
        setFullHeightLayout(!(view.window?.styleMask.contains(.fullScreen) ?? false))
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
    ///
    /// A sidebar listing one file is a list of the thing you are already
    /// looking at.
    var hasSomethingToSwitchBetween: Bool {
        guard folder != nil else { return false }
        return sidebar.tree.documentCount > 1
    }

    /// Stands in for a click on a row, so the whole path can be checked rather
    /// than only `openInPlace` underneath it. The regression this exists for was
    /// files opening in their own windows again while the direct checks passed.
    func openFromSidebarForTest(_ url: URL) { open(url) }

    /// Called when a file is chosen in the sidebar.
    ///
    /// The row that ends up lit is whichever file this window is showing when
    /// the dust settles, never the one that was clicked. Those are not the same
    /// thing: a file already open in another window raises that window and
    /// leaves this one exactly as it was, and selecting the clicked row anyway
    /// told you this window was showing a file that was in fact on the other
    /// screen.
    private func open(_ url: URL) {
        defer { syncSelection() }
        guard let window = view.window,
              let current = NSDocumentController.shared.document(for: window),
              let controller = NSDocumentController.shared as? KvillDocumentController,
              controller.openInPlace(url, replacing: current)
        else {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            return
        }
    }

    /// Lights the row for the file this window is actually showing.
    func syncSelection() { sidebar.tree.select(page.documentURL) }

    // MARK: - Two documents at once

    /// Shows a second document beside the first.
    ///
    /// Replaces whatever was there if the window is already split, which is
    /// what dropping a third file has to mean: three panes at 380 points each
    /// do not fit in a window anyone has.
    func showBeside(_ editor: DocumentViewController) {
        if let existing = companionItem {
            removeSplitViewItem(existing)
        }
        editor.isCompanion = true
        let item = Self.makePageItem(editor)
        addSplitViewItem(item)
        companionItem = item
        companion = editor
        // Even halves to begin with. Whatever the reader drags it to afterwards
        // is theirs, and AppKit remembers it for the length of the window.
        let panes = splitView.frame.width - (sidebarItem.isCollapsed ? 0 : 188)
        splitView.setPosition(splitView.frame.width - panes / 2, ofDividerAt: splitViewItems.count - 2)
    }

    /// Takes the second document away and gives the width back to the first.
    @discardableResult
    func closeCompanion() -> DocumentViewController? {
        guard let item = companionItem, let editor = companion else { return nil }
        removeSplitViewItem(item)
        companionItem = nil
        companion = nil
        editor.isCompanion = false
        return editor
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
        pageItem = Self.makePageItem(next)
        // Back in the middle, before the companion rather than after it.
        insertSplitViewItem(pageItem, at: 1)
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

    /// The pane a view belongs to, so a keystroke can be attributed to the right
    /// document. Without this, Cmd S in the second pane saved the first one.
    func pane(containing view: NSView) -> DocumentViewController? {
        var candidate: NSView? = view
        while let current = candidate {
            if current === page.view { return page }
            if let companion, current === companion.view { return companion }
            candidate = current.superview
        }
        return nil
    }

    /// Whether any pane would draw a hairline under the title bar, for the
    /// self test. Checked after a file switch as well as before one.
    var drawsTitlebarSeparator: Bool {
        splitViewItems.contains { $0.titlebarSeparatorStyle != .none }
    }
}

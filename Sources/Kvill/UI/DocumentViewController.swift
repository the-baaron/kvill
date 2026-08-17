import AppKit

/// Container for one open file: the editor filling the window, with the floating
/// chrome layered over it.
///
/// Layering, back to front: editor, scroll edge effects, stats pill, selection
/// formatting bar, display options button.
final class DocumentViewController: NSViewController {

    let editor = EditorViewController()
    private let stats = StatsPillView()
    private let optionsBar = DisplayOptionsBar()
    private let dragArea = WindowDragArea()
    private let titleLabel = NSTextField(labelWithString: "")
    private var toast: ToastView?
    /// Window-level blur behind a translucent palette. Hidden for opaque ones.
    private let backdrop = NSVisualEffectView()
    /// The palette's own colour, laid over the material so a glass page still
    /// reads as Frost or Onyx rather than as bare system blur.
    private let tint = NSView()
    /// Built on first use. Eleven SF Symbol buttons and a glass backdrop is real
    /// work, and none of it is needed until there is a selection to act on.
    private var selectionToolbar: SelectionToolbarView?
    /// The folder sidebar. Built only when a folder is opened, which most
    /// documents never do.
    private var fileTree: FileTreeView?
    private var treeWidth: NSLayoutConstraint!
    private var treeLeading: NSLayoutConstraint!
    private var treeTop: NSLayoutConstraint!
    private var treeBottom: NSLayoutConstraint!
    private var editorLeading: NSLayoutConstraint!

    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarTop: NSLayoutConstraint!
    private var mouseMonitor: Any?

    /// Fired after the editor's text changes, so the document can mark itself dirty.
    var onTextChange: (() -> Void)?

    private var theme: Theme { ThemeManager.shared.theme }

    // MARK: - Construction

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container
        dragArea.translatesAutoresizingMaskIntoConstraints = false

        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)

        tint.wantsLayer = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(tint)

        addChild(editor)
        let editorView = editor.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(editorView)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        container.addSubview(dragArea)
        container.addSubview(stats)
        container.addSubview(optionsBar)


        editorLeading = editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            editorLeading,
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: container.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 13),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -260),

            dragArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dragArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dragArea.topAnchor.constraint(equalTo: container.topAnchor),
            dragArea.heightAnchor.constraint(equalToConstant: WindowDragArea.height),

            optionsBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            optionsBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),

            stats.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stats.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),
        ])

        editor.onTextChange = { [weak self] in
            self?.updateStats()
            self?.onTextChange?()
        }
        editor.onSelectionChange = { [weak self] in self?.updateSelectionToolbar() }
        editor.onScroll = { [weak self] _, _ in
        }
        editor.textView.onSelectionGestureEnded = { [weak self] in self?.updateSelectionToolbar() }
        // Dropping a folder on the page shows its Markdown down the side, and
        // grants access to what is in it, exactly as File > Open Folder does.
        editor.textView.onFolderDrop = { folder in
            FolderAccess.remember(folder)
            // Off the drop, not inside it. A drop runs its own nested run loop
            // and AppKit lays the window out inside it, so building the sidebar
            // and activating its constraints there is mutating layout from
            // inside a layout pass: `_postWindowNeedsLayout` throws and the app
            // dies with an abort. The crash report for 7.0.0 is exactly that,
            // NSCoreDragReceiveMessageProc down to layoutIfNeeded.
            DispatchQueue.main.async {
                (NSDocumentController.shared as? KvillDocumentController)?.openFolder(folder)
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: .kvillThemeChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: .kvillPreferencesChanged, object: nil)
        // Watched here as well as through the editor's own callback: the bar
        // lives in this view's coordinates while the selection lives in the text
        // view's, so every scroll moves the text out from under it.
        editor.scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportMoved),
            name: NSView.boundsDidChangeNotification,
            object: editor.scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportMoved),
            name: NSScrollView.didLiveScrollNotification,
            object: editor.scrollView)

        applyBackdrop()
        titleLabel.textColor = theme.colors.textSecondary
        updateStats()
    }

    /// The sidebar decides between floating and pushing from the window width,
    /// so it has to be reconsidered every time that changes.
    ///
    /// In `viewWillLayout`, before the pass rather than after it. Changing a
    /// constraint from `viewDidLayout` asks a window that is laying out to lay
    /// out again, which is the same mistake that made a folder drop abort the
    /// app in 7.0.0, just reached from the other side.
    override func viewWillLayout() {
        super.viewWillLayout()
        updateSidebarReach()
        updateTreeLayout(animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(editor.textView)
        view.window?.acceptsMouseMovedEvents = true
        startMouseTracking()
        applyChromeVisibility()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopMouseTracking()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMouseTracking()
    }

    /// Hides or shows every piece of chrome at once, including the title bar,
    /// leaving nothing but the page.
    @objc func toggleInterface(_ sender: Any?) {
        ThemeManager.shared.chromeHidden.toggle()
        applyChromeVisibility()
    }

    private func applyChromeVisibility() {
        let hidden = ThemeManager.shared.chromeHidden
        optionsBar.isHidden = hidden
        stats.isHidden = hidden
        updateTitleVisibility()
        if hidden {
            optionsBar.close()
            hideSelectionToolbar()
        }

        guard let window = view.window else { return }
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = hidden
        }
    }

    @objc private func viewportMoved() {
        updateTitleVisibility()
        updateSelectionToolbar()
    }

    /// The file name belongs to the top of the document. Once you have scrolled
    /// into the text it is just something in the way, so it goes.
    private func updateTitleVisibility() {
        let scrolled = editor.scrollView.contentView.bounds.origin.y
        let wanted: CGFloat = (scrolled < 12 && !ThemeManager.shared.chromeHidden) ? 1 : 0
        guard abs(titleLabel.alphaValue - wanted) > 0.01 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            titleLabel.animator().alphaValue = wanted
        }
    }

    /// Name shown at the top of the page, in place of the window title.
    var documentTitle: String = "" {
        didSet {
            titleLabel.stringValue = documentTitle
            updateTitleVisibility()
        }
    }

    @objc private func preferencesChanged() {
        applyChromeVisibility()
    }

    @objc private func themeChanged() {
        titleLabel.textColor = theme.colors.textSecondary
        applyBackdrop()
    }

    /// Test hooks: the title fades on scroll, which is behaviour rather than
    /// structure, so it is measured rather than assumed.
    var titleAlphaForTest: CGFloat { titleLabel.alphaValue }
    func viewportMovedForTest() { viewportMoved() }

    /// Whether the window-level blur behind a translucent page is on screen.
    var hasVisibleBackdrop: Bool { !backdrop.isHidden }
    /// Whether the palette's colour is laid over that material.
    var hasVisibleTint: Bool { !tint.isHidden && tint.layer?.backgroundColor != nil }

    private func applyBackdrop() {
        let glass = theme.colors.isTranslucent
        backdrop.isHidden = !glass
        // A hidden visual effect view still keeps its blur going unless it is
        // told to stop, and most palettes are opaque, so most of the time this
        // is a blur nobody can see.
        backdrop.state = glass ? .active : .inactive
        backdrop.material = theme.colors.material
        backdrop.appearance = theme.colors.appearance

        tint.isHidden = !glass
        tint.layer?.backgroundColor = glass
            ? theme.colors.background.withAlphaComponent(theme.colors.pageAlpha).cgColor
            : nil
    }

    // MARK: - Pointer proximity

    /// The bar opens as the pointer approaches, which needs mouse positions even
    /// while the pointer is over the text view, so this watches the event stream
    /// rather than using a tracking area.
    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            self.optionsBar.updateProximity(to: self.view.convert(event.locationInWindow, from: nil))
            return event
        }
    }

    private func stopMouseTracking() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    // MARK: - Content

    /// Pending word count. Nobody reads the pill mid-word, so it is worked out
    /// once typing stops rather than on every key.
    private var statsWork: DispatchWorkItem?

    private func updateStats() {
        statsWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.stats.update(text: self.editor.text)
        }
        statsWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func loadText(_ text: String) {
        editor.setText(text)
        updateStats()
    }

    /// Takes new text from disk without throwing away where the reader was.
    func replaceKeepingPlace(with text: String) {
        editor.replaceKeepingPlace(with: text)
        updateStats()
    }

    var text: String { editor.text }

    /// Squares up every table in the document. Used on save.
    func formatTables() { editor.formatAllTables() }

    /// Answers Cmd S. There is nothing to confirm, because the document has been
    /// saving itself all along, so the toast says that rather than pretending
    /// the keystroke did the work.
    func confirmSaved() {
        makeToast().show("Your files are auto-saved, don't worry",
                         symbol: "checkmark.circle.fill")
    }

    private func makeToast() -> ToastView {
        if let toast { return toast }
        let created = ToastView()
        view.addSubview(created)
        NSLayoutConstraint.activate([
            created.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            created.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -30),
        ])
        toast = created
        return created
    }

    private func makeSelectionToolbar() -> SelectionToolbarView {
        if let selectionToolbar { return selectionToolbar }
        let created = SelectionToolbarView()
        created.alphaValue = 0
        created.isHidden = true
        // Below the options bar so the two never fight over a click.
        view.addSubview(created, positioned: .below, relativeTo: optionsBar)

        toolbarLeading = created.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: 0)
        toolbarTop = created.topAnchor.constraint(equalTo: view.topAnchor, constant: 0)
        NSLayoutConstraint.activate([toolbarLeading, toolbarTop])

        selectionToolbar = created
        return created
    }

    /// Shows the folder's Markdown files down the side, and grants Kvill the
    /// read access that makes images inside that folder load.
    func showFolder(_ folder: URL) {
        let tree = fileTree ?? {
            let made = FileTreeView()
            made.onOpen = { [weak self] url in
                // Switching reuses this window, so a folder of notes does not
                // become a screen of windows. The document that arrives brings
                // its own editor; nothing is shared between them. The sidebar has
                // to be put back either way, otherwise clicking a file in it is a
                // way of losing it.
                if let self, let window = self.view.window,
                   let current = NSDocumentController.shared.document(for: window),
                   let controller = NSDocumentController.shared as? KvillDocumentController,
                   controller.openInPlace(url, replacing: current) {
                    (window.contentViewController as? DocumentViewController)?.showFolder(folder)
                    return
                }
                NSDocumentController.shared.openDocument(
                    withContentsOf: url, display: true) { document, _, _ in
                    (document?.windowControllers.first?.contentViewController
                        as? DocumentViewController)?.showFolder(folder)
                }
            }
            view.addSubview(made, positioned: .below, relativeTo: dragArea)
            treeWidth = made.widthAnchor.constraint(equalToConstant: 220)
            // Flush to the window's edges when docked, inset as a card when it
            // is peeking over the page. The constants move between the two.
            treeLeading = made.leadingAnchor.constraint(equalTo: view.leadingAnchor)
            treeTop = made.topAnchor.constraint(
                equalTo: view.topAnchor, constant: WindowDragArea.height)
            treeBottom = made.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            NSLayoutConstraint.activate([treeLeading, treeTop, treeBottom, treeWidth])
            fileTree = made
            return made
        }()

        tree.show(folder)
        tree.select(documentURL)
        // Asking for a folder is asking to see it. A wide window is already
        // docked by default so there is nothing to say; a narrow one peeks, so
        // the folder is visibly there without taking a fifth of the page from
        // someone who did not ask for that.
        //
        // Deliberately not pinned. Pinning here made opening a folder an
        // permanent answer to a question about window width, so narrowing the
        // window afterwards could never undock it again.
        if isNarrow { sidebarPeeking = true }
        updateTreeLayout(animated: false)
        view.needsLayout = true
    }

    // MARK: - The sidebar: docked, or peeking over the page

    /// Two states, kept apart, which is the whole lesson of the first attempt.
    ///
    /// **Docked.** The sidebar owns its strip of the window. The page begins
    /// where the sidebar ends and is never underneath it.
    ///
    /// **Peeking.** The sidebar is off, and reaching for the left edge slides it
    /// in as a card over the page, inset from the window's edges with a shadow
    /// under it, until the pointer leaves. The page does not move, because the
    /// covering is momentary and was asked for.
    ///
    /// Mixing them is what went wrong: on a narrow window the page was given the
    /// full width, moving it left, and the sidebar was then drawn on top of it.
    /// The page both moved the wrong way and got covered. A page never moves
    /// towards a sidebar that is appearing.

    /// Below this a sidebar is not worth a fifth of the window by default, so it
    /// starts off and peeks instead. Above it, docked.
    private static let docksByDefaultAbove: CGFloat = 1040

    /// What the reader asked for. Nil until they say, which is when the width
    /// decides.
    private var sidebarPinned: Bool?

    /// The pointer is at the left edge and the sidebar is riding over the page.
    private var sidebarPeeking = false

    private var isNarrow: Bool { view.bounds.width < Self.docksByDefaultAbove }

    /// Docked means it takes space from the page rather than covering it.
    private var sidebarDocked: Bool {
        guard fileTree != nil else { return false }
        return sidebarPinned ?? !isNarrow
    }

    @objc func toggleFileTree(_ sender: Any?) {
        guard fileTree != nil else { return }
        sidebarPinned = !sidebarDocked
        sidebarPeeking = false
        updateTreeLayout(animated: true)
    }

    /// Places the sidebar and decides whether the page gives up room for it.
    func updateTreeLayout(animated: Bool) {
        guard let tree = fileTree else { return }
        let docked = sidebarDocked
        let visible = docked || sidebarPeeking

        // The page is inset by the sidebar only when the sidebar is docked. It
        // is never inset by less while the sidebar is on screen, which is what
        // used to slide it left into the thing covering it.
        let pageInset = docked ? treeWidth.constant : 0
        // A card when it peeks: away from the edges, with a shadow. Flush when
        // docked, because then it is part of the window rather than over it.
        let cardInset: CGFloat = docked ? 0 : 10
        let alpha: CGFloat = visible ? 1 : 0

        guard editorLeading.constant != pageInset
                || treeLeading.constant != cardInset
                || tree.alphaValue != alpha
        else { return }

        tree.isFloating = !docked

        let apply = {
            self.editorLeading.animator().constant = pageInset
            self.treeLeading.animator().constant = cardInset
            self.treeTop.animator().constant = docked
                ? WindowDragArea.height : WindowDragArea.height + cardInset
            self.treeBottom.animator().constant = -cardInset
            tree.animator().alphaValue = alpha
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.allowsImplicitAnimation = true
                apply()
            }
        } else {
            editorLeading.constant = pageInset
            treeLeading.constant = cardInset
            treeTop.constant = docked
                ? WindowDragArea.height : WindowDragArea.height + cardInset
            treeBottom.constant = -cardInset
            tree.alphaValue = alpha
        }
    }

    /// A strip down the left edge that brings the sidebar out when reached for,
    /// the same idea as the display options opening as the pointer arrives
    /// rather than only on a click.
    private func updateSidebarReach() {
        for area in view.trackingAreas where area.userInfo?["sidebarReach"] != nil {
            view.removeTrackingArea(area)
        }
        guard fileTree != nil else { return }
        // Wide enough to be reachable without being in the way, and while the
        // sidebar is out it covers the sidebar too, so crossing onto the file
        // names does not read as leaving.
        let width: CGFloat = sidebarPeeking ? treeWidth.constant + 30 : 24
        view.addTrackingArea(NSTrackingArea(
            rect: NSRect(x: 0, y: 0, width: width, height: view.bounds.height),
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: ["sidebarReach": true]))
    }

    override func mouseEntered(with event: NSEvent) {
        guard event.trackingArea?.userInfo?["sidebarReach"] != nil,
              !sidebarDocked, !sidebarPeeking else { return }
        sidebarPeeking = true
        updateTreeLayout(animated: true)
        updateSidebarReach()
    }

    override func mouseExited(with event: NSEvent) {
        guard event.trackingArea?.userInfo?["sidebarReach"] != nil, sidebarPeeking else { return }
        sidebarPeeking = false
        updateTreeLayout(animated: true)
        updateSidebarReach()
    }

    /// Where the sidebar and the page have actually ended up, for the self test.
    var sidebarStateForTest: (docked: Bool, visible: Bool, pageInset: CGFloat, cardInset: CGFloat) {
        (sidebarDocked,
         (fileTree?.alphaValue ?? 0) > 0,
         editorLeading.constant,
         treeLeading?.constant ?? 0)
    }

    /// Stands in for the pointer arriving at the left edge.
    func peekSidebarForTest() {
        guard !sidebarDocked else { return }
        sidebarPeeking = true
        updateTreeLayout(animated: false)
    }

    /// Whether the sidebar is showing, for the self test.
    var isShowingFileTree: Bool { fileTree != nil && (fileTree?.alphaValue ?? 0) > 0 }

    /// Where the file lives, for resolving and filing images.
    var documentURL: URL? {
        get { editor.documentURL }
        set { editor.documentURL = newValue }
    }

    // MARK: - Selection toolbar

    private func updateSelectionToolbar() {
        guard !editor.textView.isSelectingWithMouse,
              let selection = editor.selectionRect(in: view) else {
            hideSelectionToolbar()
            return
        }

        let bar = makeSelectionToolbar()
        let size = bar.fittingSize
        let bounds = view.bounds
        guard size.width > 0, bounds.width > size.width + 24 else {
            hideSelectionToolbar()
            return
        }

        // Auto Layout anchors are visual, so positions are measured from the
        // visual top even though this view is not flipped.
        var leading = selection.midX - size.width / 2
        leading = min(max(leading, 12), bounds.width - size.width - 12)

        let selectionTopInset = bounds.height - selection.maxY
        var top = selectionTopInset - size.height - 10
        if top < 12 {
            // Not enough headroom, so sit under the selection instead.
            top = bounds.height - selection.minY + 10
        }
        top = min(max(top, 12), max(12, bounds.height - size.height - 12))

        toolbarLeading.constant = leading
        toolbarTop.constant = top
        showSelectionToolbar()
    }

    private func showSelectionToolbar() {
        let bar = makeSelectionToolbar()
        guard bar.isHidden || bar.alphaValue < 1 else { return }
        bar.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bar.animator().alphaValue = 1
        }
    }

    private func hideSelectionToolbar() {
        // Never built means never shown, so there is nothing to hide.
        guard let bar = selectionToolbar, !bar.isHidden else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            bar.animator().alphaValue = 0
        }, completionHandler: {
            bar.isHidden = true
        })
    }

    // MARK: - Display options

    @objc func toggleThemePanel(_ sender: Any?) {
        optionsBar.isOpen ? optionsBar.close() : optionsBar.present()
    }

    override func cancelOperation(_ sender: Any?) {
        if optionsBar.isOpen {
            optionsBar.close()
        } else {
            super.cancelOperation(sender)
        }
    }
}

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
    /// Opens and closes the sidebar. Mirrors the options button on the other
    /// side, at the same height, so the two top corners match.
    private let sidebarToggle = SidebarToggleButton()
    private let dragArea = WindowDragArea()
    private let titleLabel = NSTextField(labelWithString: "")
    private var toast: ToastView?
    /// reads as Frost or Onyx rather than as bare system blur.
    /// Built on first use. Eleven SF Symbol buttons and a glass backdrop is real
    /// work, and none of it is needed until there is a selection to act on.
    private var selectionToolbar: SelectionToolbarView?
    /// The folder sidebar. Built only when a folder is opened, which most
    /// documents never do.
    private var editorLeading: NSLayoutConstraint!
    /// How far the sidebar button sits from the page's leading edge. It has
    /// to clear the traffic lights when the page starts at the window edge.
    private var sidebarToggleLeading: NSLayoutConstraint!
    /// Distance from the top of the page to the floating buttons, set so their
    /// centre lands on the traffic lights' centre.
    private var chromeTop: NSLayoutConstraint!

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
        container.addSubview(sidebarToggle)


        editorLeading = editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        sidebarToggleLeading = sidebarToggle.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: Self.toggleClearOfLights)
        chromeTop = optionsBar.topAnchor.constraint(
            equalTo: container.topAnchor, constant: Self.chromeTopFallback)

        NSLayoutConstraint.activate([
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
            chromeTop,

            sidebarToggleLeading,
            sidebarToggle.topAnchor.constraint(equalTo: optionsBar.topAnchor),

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

    /// Beside the traffic lights, or clear of them.
    ///
    /// With the sidebar open the page starts where the sidebar ends, so the
    /// button can sit at the page's own margin. With it collapsed the page fills
    /// the window and that margin is exactly where the traffic lights are: the
    /// button landed on top of them.
    private static let toggleBesideText: CGFloat = 18
    private static let toggleClearOfLights: CGFloat = 88
    /// Until the window exists and the real buttons can be measured.
    private static let chromeTopFallback: CGFloat = 16

    override func viewWillLayout() {
        super.viewWillLayout()
        // Before the pass, never after it. A constraint changed from
        // viewDidLayout asks a window that is laying out to lay out again, and
        // that is an abort.
        let split = view.window?.contentViewController as? DocumentSplitViewController
        // No sidebar worth opening means no button offering to open it.
        sidebarToggle.isHidden = ThemeManager.shared.chromeHidden
            || !(split?.hasSomethingToSwitchBetween ?? false)
        let sidebarOpen = split?.isShowingFileTree ?? false
        let wanted = sidebarOpen ? Self.toggleBesideText : Self.toggleClearOfLights
        if sidebarToggleLeading.constant != wanted {
            sidebarToggleLeading.constant = wanted
        }
        alignChromeWithTrafficLights()
    }

    /// Puts the floating buttons on the same centre line as the traffic lights.
    ///
    /// Measured off the real buttons rather than written as a number, because
    /// the title bar's height is the system's to decide and changes with the
    /// toolbar style and the OS version. `standardWindowButton` is where they
    /// actually are.
    private func alignChromeWithTrafficLights() {
        guard let window = view.window,
              let close = window.standardWindowButton(.closeButton) else { return }
        let inWindow = close.convert(close.bounds, to: nil)
        let inContainer = view.convert(inWindow, from: nil)
        // The container is not flipped, so the top edge is maxY.
        let fromTop = view.bounds.maxY - inContainer.midY
        let wanted = (fromTop - SidebarToggleButton.size / 2).rounded()
        guard wanted > 0, abs(chromeTop.constant - wanted) > 0.5 else { return }
        chromeTop.constant = wanted
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

    private func applyBackdrop() {
        view.layer?.backgroundColor = theme.colors.background.cgColor
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

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
    /// Also built on first use: most documents have no table in them at all.
    private var tableBadge: TableBadgeView?

    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarTop: NSLayoutConstraint!
    private var badgeLeading: NSLayoutConstraint!
    private var badgeTop: NSLayoutConstraint!
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


        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            tint.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tint.topAnchor.constraint(equalTo: container.topAnchor),
            tint.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
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
        editor.onSelectionChange = { [weak self] in
            self?.updateSelectionToolbar()
            self?.updateTableBadge()
        }
        editor.onScroll = { [weak self] _, _ in
        }
        editor.textView.onSelectionGestureEnded = { [weak self] in self?.updateSelectionToolbar() }

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: .quillThemeChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: .quillPreferencesChanged, object: nil)
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
        updateTableBadge()
    }

    // MARK: - Table badge

    private func makeTableBadge() -> TableBadgeView {
        if let tableBadge { return tableBadge }
        let created = TableBadgeView()
        created.alphaValue = 0
        created.isHidden = true
        created.onClick = { [weak self] in self?.editor.editTableAtCaret() }
        view.addSubview(created, positioned: .below, relativeTo: optionsBar)

        badgeLeading = created.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        badgeTop = created.topAnchor.constraint(equalTo: view.topAnchor)
        NSLayoutConstraint.activate([badgeLeading, badgeTop])

        tableBadge = created
        return created
    }

    /// Puts the badge on the table's top-right corner while the caret is inside
    /// it. Hidden the rest of the time, which is nearly always.
    private func updateTableBadge() {
        guard !ThemeManager.shared.chromeHidden,
              let table = editor.caretTableRect(in: view) else {
            hideTableBadge()
            return
        }

        let badge = makeTableBadge()
        let size = badge.fittingSize
        let bounds = view.bounds
        guard size.width > 0 else { return }

        // Anchors are measured from the visual top, and this view is not flipped.
        let leading = min(max(12, table.maxX - size.width), bounds.width - size.width - 12)
        var top = bounds.height - table.maxY - size.height - 6
        // A table starting at the very top of the window has no room above it,
        // so the badge tucks just inside its first row instead.
        if top < 12 { top = bounds.height - table.maxY + 4 }
        guard top > 0, top < bounds.height - size.height else {
            hideTableBadge()
            return
        }

        badgeLeading.constant = leading
        badgeTop.constant = top
        showTableBadge()
    }

    private func showTableBadge() {
        let badge = makeTableBadge()
        guard badge.isHidden || badge.alphaValue < 1 else { return }
        badge.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            badge.animator().alphaValue = 1
        }
    }

    private func hideTableBadge() {
        guard let badge = tableBadge, !badge.isHidden else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            badge.animator().alphaValue = 0
        }, completionHandler: {
            badge.isHidden = true
        })
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

    private func updateStats() {
        stats.update(text: editor.text)
    }

    func loadText(_ text: String) {
        editor.setText(text)
        updateStats()
    }

    var text: String { editor.text }

    /// Brief confirmation that a save happened, since saving is otherwise silent.
    func confirmSaved() {
        makeToast().show("Saved", symbol: "checkmark.circle.fill")
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

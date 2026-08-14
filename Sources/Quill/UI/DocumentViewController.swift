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
    private let toast = ToastView()
    /// Window-level blur behind a translucent palette. Hidden for opaque ones.
    private let backdrop = NSVisualEffectView()
    private let selectionToolbar = SelectionToolbarView()
    private var topEdge: ScrollEdgeEffectView!
    private var bottomEdge: ScrollEdgeEffectView!

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

        topEdge = ScrollEdgeEffectView(edge: .top, theme: theme)
        bottomEdge = ScrollEdgeEffectView(edge: .bottom, theme: theme)

        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(backdrop)

        addChild(editor)
        let editorView = editor.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(editorView)
        container.addSubview(dragArea)
        container.addSubview(topEdge)
        container.addSubview(bottomEdge)
        container.addSubview(stats)
        container.addSubview(selectionToolbar)
        container.addSubview(optionsBar)
        container.addSubview(toast)

        selectionToolbar.alphaValue = 0
        selectionToolbar.isHidden = true

        toolbarLeading = selectionToolbar.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: 0)
        toolbarTop = selectionToolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 0)

        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: container.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: container.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            dragArea.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            dragArea.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            dragArea.topAnchor.constraint(equalTo: container.topAnchor),
            dragArea.heightAnchor.constraint(equalToConstant: WindowDragArea.height),

            topEdge.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topEdge.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            topEdge.topAnchor.constraint(equalTo: container.topAnchor),
            topEdge.heightAnchor.constraint(equalToConstant: 84),

            bottomEdge.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomEdge.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomEdge.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomEdge.heightAnchor.constraint(equalToConstant: 68),

            optionsBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            optionsBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),

            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -30),

            stats.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            stats.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22),

            toolbarLeading,
            toolbarTop,
        ])

        editor.onTextChange = { [weak self] in
            self?.updateStats()
            self?.onTextChange?()
        }
        editor.onSelectionChange = { [weak self] in self?.updateSelectionToolbar() }
        editor.onScroll = { [weak self] underTop, underBottom in
            self?.topEdge.setActive(underTop)
            self?.bottomEdge.setActive(underBottom)
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
        if hidden {
            optionsBar.close()
            hideSelectionToolbar()
        }

        guard let window = view.window else { return }
        window.titleVisibility = hidden ? .hidden : .visible
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = hidden
        }
    }

    @objc private func viewportMoved() {
        updateSelectionToolbar()
    }

    @objc private func preferencesChanged() {
        applyChromeVisibility()
    }

    @objc private func themeChanged() {
        topEdge.theme = theme
        bottomEdge.theme = theme
        applyBackdrop()
    }

    private func applyBackdrop() {
        backdrop.isHidden = !theme.colors.isTranslucent
        backdrop.material = theme.colors.material
        backdrop.appearance = theme.colors.appearance
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
        toast.show("Saved", symbol: "checkmark.circle.fill")
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

        let size = selectionToolbar.fittingSize
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
        guard selectionToolbar.isHidden || selectionToolbar.alphaValue < 1 else { return }
        selectionToolbar.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            selectionToolbar.animator().alphaValue = 1
        }
    }

    private func hideSelectionToolbar() {
        guard !selectionToolbar.isHidden else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            selectionToolbar.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.selectionToolbar.isHidden = true
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

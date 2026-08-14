import AppKit

/// Container for one open file: the editor filling the window, with the floating
/// chrome layered over it.
///
/// Layering, back to front: editor, scroll edge effects, stats pill, selection
/// formatting bar, display options bar, settings panel.
final class DocumentViewController: NSViewController {

    let editor = EditorViewController()
    private let panel = ThemePanelView()
    private let stats = StatsPillView()
    private let optionsBar = DisplayOptionsBar()
    private let selectionToolbar = SelectionToolbarView()
    private var topEdge: ScrollEdgeEffectView!
    private var bottomEdge: ScrollEdgeEffectView!

    private var panelBottom: NSLayoutConstraint!
    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarTop: NSLayoutConstraint!
    private var mouseMonitor: Any?

    private(set) var isPanelVisible = false

    /// Fired after the editor's text changes, so the document can mark itself dirty.
    var onTextChange: (() -> Void)?

    private var theme: Theme { ThemeManager.shared.theme }

    // MARK: - Construction

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        view = container

        topEdge = ScrollEdgeEffectView(edge: .top, theme: theme)
        bottomEdge = ScrollEdgeEffectView(edge: .bottom, theme: theme)

        addChild(editor)
        let editorView = editor.view
        editorView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(editorView)
        container.addSubview(topEdge)
        container.addSubview(bottomEdge)
        container.addSubview(stats)
        container.addSubview(selectionToolbar)
        container.addSubview(optionsBar)
        container.addSubview(panel)

        panel.alphaValue = 0
        panel.isHidden = true
        panel.onClose = { [weak self] in self?.hidePanel() }

        selectionToolbar.alphaValue = 0
        selectionToolbar.isHidden = true

        optionsBar.onShowFullPanel = { [weak self] in self?.showPanel() }

        panelBottom = panel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -22)
        toolbarLeading = selectionToolbar.leadingAnchor.constraint(
            equalTo: container.leadingAnchor, constant: 0)
        toolbarTop = selectionToolbar.topAnchor.constraint(equalTo: container.topAnchor, constant: 0)

        NSLayoutConstraint.activate([
            editorView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            editorView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: container.topAnchor),
            editorView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

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

            panel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            panelBottom,

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

        updateStats()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(editor.textView)
        view.window?.acceptsMouseMovedEvents = true
        startMouseTracking()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        stopMouseTracking()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopMouseTracking()
    }

    @objc private func themeChanged() {
        topEdge.theme = theme
        bottomEdge.theme = theme
    }

    // MARK: - Pointer proximity

    /// The options bar opens when the pointer approaches, which needs mouse
    /// positions even while the pointer is over the text view, so this watches
    /// the event stream rather than using a tracking area.
    private func startMouseTracking() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            guard let self, event.window === self.view.window else { return event }
            let point = self.view.convert(event.locationInWindow, from: nil)
            self.optionsBar.updateProximity(to: point)
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

    // MARK: - Settings panel

    @objc func toggleThemePanel(_ sender: Any?) {
        isPanelVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        guard !isPanelVisible else { return }
        isPanelVisible = true
        panel.sync()
        panel.isHidden = false
        panel.alphaValue = 0
        view.layoutSubtreeIfNeeded()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hidePanel() {
        guard isPanelVisible else { return }
        isPanelVisible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.panel.isHidden = true
        })
    }

    override func cancelOperation(_ sender: Any?) {
        if isPanelVisible {
            hidePanel()
        } else {
            super.cancelOperation(sender)
        }
    }
}

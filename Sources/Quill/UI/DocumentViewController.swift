import AppKit

/// Container for one open file: the editor filling the window, with the floating
/// chrome layered over it.
///
/// Layering, back to front: editor, scroll edge effects, stats pill, selection
/// formatting bar, display options button.
final class DocumentViewController: NSViewController {

    let editor = EditorViewController()
    private let stats = StatsPillView()
    private let optionsButton = DisplayOptionsButton()
    private let selectionToolbar = SelectionToolbarView()
    private var topEdge: ScrollEdgeEffectView!
    private var bottomEdge: ScrollEdgeEffectView!

    private var toolbarLeading: NSLayoutConstraint!
    private var toolbarTop: NSLayoutConstraint!

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
        container.addSubview(optionsButton)

        selectionToolbar.alphaValue = 0
        selectionToolbar.isHidden = true

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

            optionsButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            optionsButton.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),

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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeChanged() {
        topEdge.theme = theme
        bottomEdge.theme = theme
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

    // MARK: - Display options

    @objc func toggleThemePanel(_ sender: Any?) {
        optionsButton.toggle()
    }

    override func cancelOperation(_ sender: Any?) {
        if optionsButton.isOpen {
            optionsButton.close()
        } else {
            super.cancelOperation(sender)
        }
    }
}

import AppKit

/// Hosts the text view and owns the parse → style → decorate cycle.
final class EditorViewController: NSViewController {

    let textView: EditorTextView
    let scrollView: NSScrollView

    private let styler: MarkdownStyler
    private(set) var parsed = ParsedDocument(lines: [])
    /// Blocks the selection touches. Their syntax markers are revealed.
    private var activeBlockIDs: Set<Int> = []
    /// Line range covered by each block, so a block can be restyled on its own.
    private var blockLineRanges: [Int: Range<Int>] = [:]
    private var isStyling = false
    private var isAutoScrolling = false
    private var lastContentWidth: CGFloat = -1

    private var theme: Theme { ThemeManager.shared.theme }

    /// Where the document lives, so relative image paths can be resolved and
    /// dropped images can be filed next to it.
    var documentURL: URL? {
        didSet {
            styler.baseURL = documentURL?.deletingLastPathComponent()
            ImageStore.shared.forgetFailures()
            refresh(fullRestyle: true)
        }
    }

    /// Fired whenever the text changes, so the document can mark itself dirty.
    var onTextChange: (() -> Void)?
    /// Fired when the selection changes, with whether a formatting bar should show.
    var onSelectionChange: (() -> Void)?
    /// Fired on scroll, with whether content extends past the top and bottom edges.
    var onScroll: ((_ underTop: Bool, _ underBottom: Bool) -> Void)?

    // MARK: - Construction

    init() {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        // Lay out only what is being looked at. Asking for a glyph rect forces
        // layout of that range, so decorations still measure correctly, and a
        // large document no longer has to be laid out end to end before its
        // window can appear.
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)

        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        textView = EditorTextView(frame: .zero, textContainer: container)
        scrollView = NSScrollView()
        styler = MarkdownStyler(theme: ThemeManager.shared.theme)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.textStorage?.delegate = self
        textView.theme = theme
        textView.onToggleTask = { [weak self] range in self?.toggleTask(at: range) }
        textView.typewriterScroll = { [weak self] _ in self?.centerCaret() ?? false }
        textView.onImageDrop = { [weak self] info, index in
            self?.insertDroppedImages(info, at: index) ?? false
        }

        scrollView.contentView = TypewriterClipView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = !theme.colors.isTranslucent
        scrollView.backgroundColor = theme.colors.page
        scrollView.automaticallyAdjustsContentInsets = false
        // The soft edges are drawn from the content underneath them, so a
        // scrolled region that is merely copied would leave a stale blur.
        scrollView.contentView.copiesOnScroll = false
        scrollView.scrollerStyle = .overlay

        view = scrollView

        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged),
            name: .quillThemeChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged),
            name: .quillPreferencesChanged, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipViewBoundsChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateInsets()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Content

    /// Replaces the whole document. Used when a file is loaded or reverted.
    func setText(_ text: String) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: text)
        storage.endEditing()
        textView.undoManager?.removeAllActions()
        refresh(fullRestyle: true)
    }

    var text: String {
        textView.string
    }

    // MARK: - Layout

    private func updateInsets() {
        let metrics = theme.metrics
        let available = scrollView.contentSize.width
        let horizontal = max(24, (available - metrics.contentWidth) / 2)
        let vertical: CGFloat = 56

        if textView.textContainerInset.width != horizontal
            || textView.textContainerInset.height != vertical {
            textView.textContainerInset = NSSize(width: horizontal, height: vertical)
        }

        // Room to scroll past the last line, so the end of a document can be
        // worked on without it being pinned to the bottom edge of the window.
        // Typewriter mode needs at least half a screen of this for the caret to
        // reach the middle.
        if let clip = scrollView.contentView as? TypewriterClipView {
            clip.bottomSlack = max(0, scrollView.frame.height * 0.7)
        }

        if lastContentWidth != metrics.contentWidth {
            lastContentWidth = metrics.contentWidth
            textView.needsDisplay = true
        }
    }

    // MARK: - Parse and style

    /// Reparses the document and restyles it.
    func refresh(fullRestyle: Bool) {
        guard let storage = textView.textStorage else { return }
        isStyling = true
        defer { isStyling = false }

        let text = storage.string as NSString
        parsed = MarkdownParser.parse(text)
        textView.document = parsed
        indexBlocks()
        recomputeActiveBlocks()

        styler.update(theme: theme)
        styler.prepareTables(parsed, text: text)
        let context = makeContext()

        styler.style(storage, document: parsed, lines: 0..<parsed.lines.count, context: context)

        if ThemeManager.shared.focusMode {
            styler.applyFocusDimming(
                storage, document: parsed, lines: 0..<parsed.lines.count,
                activeParagraphID: context.activeParagraphID)
        }

        rebuildDecorations()
        rebuildOverlays(context: context)
    }

    private func makeContext() -> MarkdownStyler.Context {
        MarkdownStyler.Context(
            activeBlockIDs: activeBlockIDs,
            activeParagraphID: caretParagraphID(),
            focusMode: ThemeManager.shared.focusMode,
            alwaysShowMarkers: ThemeManager.shared.alwaysShowMarkers
        )
    }

    private func caretParagraphID() -> Int? {
        let caret = textView.selectedRange().location
        guard let index = parsed.lineIndex(at: caret) else { return nil }
        return parsed.lines[index].paragraphID
    }

    /// Records the line span of every block so one block can be restyled alone.
    private func indexBlocks() {
        blockLineRanges.removeAll(keepingCapacity: true)
        var index = 0
        while index < parsed.lines.count {
            let id = parsed.lines[index].blockID
            var end = index
            while end < parsed.lines.count, parsed.lines[end].blockID == id { end += 1 }
            blockLineRanges[id] = index..<end
            index = end
        }
    }

    @discardableResult
    private func recomputeActiveBlocks() -> Set<Int> {
        let selection = textView.selectedRange()
        var result: Set<Int> = []
        for index in parsed.lineIndices(in: selection) {
            result.insert(parsed.lines[index].blockID)
        }
        activeBlockIDs = result
        return result
    }

    private func rebuildOverlays(context: MarkdownStyler.Context) {
        var result: [TextOverlay] = []
        for line in parsed.lines {
            if MarkdownStyler.drawsBulletDot(line, context: context), line.markerRange.length > 0 {
                result.append(.bullet(line.markerRange))
            }
            if line.blockImage != nil, let display = styler.imageDisplay(for: line) {
                result.append(.image(line.range, display.url, display.size))
            }
            for token in line.inlines {
                switch token.kind {
                case .taskMarker(let state):
                    result.append(.checkbox(token.range, state))
                case .calloutLabel(let kind):
                    // Only when the raw label is hidden; otherwise it shows itself.
                    if !context.activeBlockIDs.contains(line.blockID), !context.alwaysShowMarkers {
                        result.append(.calloutTitle(token.range, kind))
                    }
                default:
                    break
                }
            }
        }
        textView.overlays = result
    }

    private func rebuildDecorations() {
        var result: [BlockDecoration] = []
        var index = 0

        while index < parsed.lines.count {
            guard let kind = parsed.lines[index].decoration else {
                index += 1
                continue
            }
            let blockID = parsed.lines[index].blockID
            var end = index
            var maxDepth = 0
            while end < parsed.lines.count, parsed.lines[end].blockID == blockID,
                  parsed.lines[end].decoration != nil {
                maxDepth = max(maxDepth, parsed.lines[end].quoteDepth)
                end += 1
            }
            let ranges = (index..<end).map { parsed.lines[$0].range }

            if case .blockquote = kind {
                // One bar per nesting level, each spanning only the lines that
                // actually reach that depth.
                for level in 1...max(maxDepth, 1) {
                    var runStart = index
                    while runStart < end {
                        guard parsed.lines[runStart].quoteDepth >= level else {
                            runStart += 1
                            continue
                        }
                        var runEnd = runStart
                        while runEnd < end, parsed.lines[runEnd].quoteDepth >= level { runEnd += 1 }
                        result.append(BlockDecoration(
                            kind: .blockquote(depth: level),
                            lineRanges: (runStart..<runEnd).map { parsed.lines[$0].range },
                            quoteDepth: level,
                            headerRow: nil))
                        runStart = runEnd
                    }
                }
            } else if case .thematicBreak = kind {
                for range in ranges {
                    result.append(BlockDecoration(
                        kind: .thematicBreak, lineRanges: [range], quoteDepth: 0, headerRow: nil))
                }
            } else {
                // A table whose header row is blank gets no header band: it is a
                // two-column layout, not a titled table.
                let hasHeader = kind == .table
                    && !styler.emptyHeaderBlocks.contains(blockID)
                result.append(BlockDecoration(
                    kind: kind, lineRanges: ranges, quoteDepth: maxDepth,
                    headerRow: hasHeader ? 0 : nil))
            }
            index = end
        }

        textView.decorations = result
    }

    // MARK: - Notifications

    @objc private func themeChanged() {
        textView.theme = theme
        scrollView.drawsBackground = !theme.colors.isTranslucent
        scrollView.backgroundColor = theme.colors.page
        styler.update(theme: theme)
        updateInsets()
        refresh(fullRestyle: true)
    }

    @objc private func preferencesChanged() {
        updateInsets()
        refresh(fullRestyle: true)
        if ThemeManager.shared.typewriterScrolling { centerCaret() }
    }

    // MARK: - Caret tracking

    /// Moving the selection changes which markers are revealed, so the blocks the
    /// selection just left and just entered are restyled. Nothing else is touched.
    private func updateActiveBlocks() {
        let previous = activeBlockIDs
        let current = recomputeActiveBlocks()
        guard current != previous else { return }

        guard let storage = textView.textStorage, !parsed.lines.isEmpty else { return }
        isStyling = true
        defer { isStyling = false }

        let context = makeContext()

        if ThemeManager.shared.focusMode {
            // Focus mode re-dims the whole document, so it all has to be restyled.
            styler.style(storage, document: parsed, lines: 0..<parsed.lines.count, context: context)
            styler.applyFocusDimming(
                storage, document: parsed, lines: 0..<parsed.lines.count,
                activeParagraphID: context.activeParagraphID)
        } else {
            for id in current.symmetricDifference(previous) {
                guard let range = blockLineRanges[id] else { continue }
                styler.style(storage, document: parsed, lines: range, context: context)
            }
        }

        // Bullets and callout titles are drawn only where the raw marker is
        // hidden, so the overlay list changes with the selection too.
        rebuildOverlays(context: context)
    }

    // MARK: - Scroll edges

    private func reportScrollEdges() {
        let clip = scrollView.contentView
        let visible = clip.bounds
        let documentHeight = textView.frame.height
        let underTop = visible.minY > 2
        let underBottom = visible.maxY < documentHeight - 2
        onScroll?(underTop, underBottom)
    }

    @objc private func clipViewBoundsChanged() {
        reportScrollEdges()
    }

    /// Rect of the current selection in the given view's coordinates, for
    /// positioning the floating formatting bar.
    func selectionRect(in target: NSView) -> NSRect? {
        let selection = textView.selectedRange()
        guard selection.length > 0, let rect = textView.rect(for: selection) else { return nil }
        return textView.convert(rect, to: target)
    }

    /// Keeps the caret's line in the middle of the window.
    ///
    /// Returns true when it has taken responsibility for scrolling, which stops
    /// the text view doing its own scroll-to-caret on top. Two things keep this
    /// from juddering: the target comes from the caret's *line fragment*, which
    /// does not move while typing along a line, so no scroll happens at all
    /// until the caret changes line; and the move is a direct, unanimated
    /// `setBoundsOrigin`, so there is no animation to interrupt on the next
    /// keystroke.
    @discardableResult
    private func centerCaret() -> Bool {
        guard ThemeManager.shared.typewriterScrolling else { return false }
        guard !isAutoScrolling else { return true }
        // Recentring mid-drag would pull the text out from under the pointer.
        guard !textView.isSelectingWithMouse else { return true }
        guard let clip = scrollView.contentView as? TypewriterClipView else { return false }

        let caret = textView.selectedRange().location
        guard let fragment = textView.lineFragmentRect(atCharacterIndex: caret) else { return false }

        let visibleHeight = clip.bounds.height
        guard visibleHeight > 0 else { return false }

        let maxY = max(0, textView.frame.height + clip.bottomSlack - visibleHeight)
        let target = min(max(fragment.midY - visibleHeight / 2, 0), maxY)
        guard abs(clip.bounds.origin.y - target) > 0.5 else { return true }

        isAutoScrolling = true
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: target))
        scrollView.reflectScrolledClipView(clip)
        isAutoScrolling = false
        return true
    }

    // MARK: - Dropped images

    /// Inserts Markdown for a dropped image on its own line at the drop point.
    private func insertDroppedImages(_ info: NSDraggingInfo, at index: Int) -> Bool {
        guard let markdown = ImageDrop.markdown(for: info, documentURL: documentURL),
              let storage = textView.textStorage else { return false }

        let text = textView.string as NSString
        let location = min(max(index, 0), text.length)

        // An image reads as a block, so give it its own line either side.
        let needsLeading = location > 0 && text.character(at: location - 1) != 10
        let needsTrailing = location < text.length && text.character(at: location) != 10
        let insertion = (needsLeading ? "\n" : "") + markdown + (needsTrailing ? "\n" : "")

        let range = NSRange(location: location, length: 0)
        guard textView.shouldChangeText(in: range, replacementString: insertion) else { return false }
        storage.replaceCharacters(in: range, with: insertion)
        textView.didChangeText()
        textView.setSelectedRange(
            NSRange(location: location + (insertion as NSString).length, length: 0))

        window?.makeFirstResponder(textView)
        return true
    }

    private var window: NSWindow? { textView.window }

    // MARK: - Task toggling

    private func toggleTask(at range: NSRange) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let marker = text.substring(with: range)
        guard let open = marker.range(of: "[") , let close = marker.range(of: "]") else { return }

        let stateIndex = marker.index(after: open.lowerBound)
        guard stateIndex < close.lowerBound else { return }

        let current = marker[stateIndex]
        let replacement = current == " " ? "x" : " "
        let location = range.location + marker.distance(from: marker.startIndex, to: stateIndex)
        let target = NSRange(location: location, length: 1)

        guard textView.shouldChangeText(in: target, replacementString: replacement) else { return }
        storage.replaceCharacters(in: target, with: replacement)
        textView.didChangeText()
    }
}

// MARK: - NSTextStorageDelegate

extension EditorViewController: NSTextStorageDelegate {
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters), !isStyling else { return }
        refresh(fullRestyle: false)
        onTextChange?()
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {

    func textViewDidChangeSelection(_ notification: Notification) {
        updateActiveBlocks()
        centerCaret()
        onSelectionChange?()
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            return continueListOnReturn()
        case #selector(NSResponder.insertTab(_:)):
            return indentListItem(by: 1)
        case #selector(NSResponder.insertBacktab(_:)):
            return indentListItem(by: -1)
        default:
            return false
        }
    }

    /// Pressing Return inside a list or quote repeats its marker; pressing it on
    /// an empty item ends the list instead of adding another empty bullet.
    private func continueListOnReturn() -> Bool {
        let caret = textView.selectedRange()
        guard caret.length == 0, let index = parsed.lineIndex(at: caret.location) else { return false }
        let line = parsed.lines[index]
        guard caret.location == NSMaxRange(line.range) else { return false }

        let text = textView.string as NSString
        var prefix: String?

        switch line.kind {
        case .listItem(let ordered, let task):
            if line.contentRange.length == 0 || (task != nil && isOnlyCheckbox(line, text: text)) {
                // Empty item: clear the marker and stop the list.
                let target = NSRange(location: line.range.location, length: line.range.length)
                guard textView.shouldChangeText(in: target, replacementString: "") else { return true }
                textView.textStorage?.replaceCharacters(in: target, with: "")
                textView.didChangeText()
                return true
            }
            let marker = text.substring(with: line.markerRange)
            let indent = String(repeating: " ", count: line.markerRange.location - line.range.location)
            if ordered, let number = Int(marker.dropLast()) {
                let delimiter = marker.last.map(String.init) ?? "."
                prefix = "\(indent)\(number + 1)\(delimiter) "
            } else {
                prefix = "\(indent)\(marker) "
            }
            if task != nil { prefix?.append("[ ] ") }

        case .blockquote, .calloutTitle:
            if line.contentRange.length == 0 {
                let target = line.range
                guard textView.shouldChangeText(in: target, replacementString: "") else { return true }
                textView.textStorage?.replaceCharacters(in: target, with: "")
                textView.didChangeText()
                return true
            }
            prefix = String(repeating: "> ", count: max(line.quoteDepth, 1))

        default:
            return false
        }

        guard let prefix else { return false }
        let insertion = "\n" + prefix
        guard textView.shouldChangeText(in: caret, replacementString: insertion) else { return true }
        textView.textStorage?.replaceCharacters(in: caret, with: insertion)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: caret.location + (insertion as NSString).length, length: 0))
        return true
    }

    private func isOnlyCheckbox(_ line: MDLine, text: NSString) -> Bool {
        let content = text.substring(with: line.contentRange).trimmingCharacters(in: .whitespaces)
        return content == "[ ]" || content == "[x]" || content == "[X]"
    }

    /// Tab indents the list item the caret sits in; Shift-Tab outdents it.
    private func indentListItem(by direction: Int) -> Bool {
        let caret = textView.selectedRange()
        guard let index = parsed.lineIndex(at: caret.location) else { return false }
        let line = parsed.lines[index]
        guard case .listItem = line.kind else { return false }

        let storage = textView.textStorage
        if direction > 0 {
            let target = NSRange(location: line.range.location, length: 0)
            guard textView.shouldChangeText(in: target, replacementString: "  ") else { return true }
            storage?.replaceCharacters(in: target, with: "  ")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: caret.location + 2, length: 0))
        } else {
            let text = textView.string as NSString
            var count = 0
            var cursor = line.range.location
            while cursor < NSMaxRange(line.range), count < 2, text.character(at: cursor) == 32 {
                cursor += 1
                count += 1
            }
            guard count > 0 else { return true }
            let target = NSRange(location: line.range.location, length: count)
            guard textView.shouldChangeText(in: target, replacementString: "") else { return true }
            storage?.replaceCharacters(in: target, with: "")
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: max(line.range.location, caret.location - count), length: 0))
        }
        return true
    }
}

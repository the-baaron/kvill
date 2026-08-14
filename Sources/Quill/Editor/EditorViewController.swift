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
    /// The span of lines whose attributes are known to be current. Styling is
    /// kept to what has been edited and what is on screen, so a keystroke does
    /// not rewrite the whole document.
    private var styledLines: Range<Int> = 0..<0
    private var isStyling = false
    /// Set while a table is being padded, so the edit does not trigger another.
    private var isFormatting = false
    /// Line of the table the caret was in last, so leaving one can be noticed.
    private var caretTableLineNumber: Int?
    /// Held so the popover is not deallocated the moment it is shown.
    private var tablePopover: NSPopover?
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
    ///
    /// `editedRange` keeps the restyle to the lines that changed and the lines
    /// on screen. Rewriting attributes across the whole document on every
    /// keystroke made AppKit treat the entire text as edited and scroll to the
    /// end of it, which is no way to type.
    func refresh(fullRestyle: Bool, editedRange: NSRange? = nil) {
        guard let storage = textView.textStorage else { return }
        isStyling = true
        defer { isStyling = false }

        let text = storage.string as NSString
        parsed = MarkdownParser.parse(text)
        textView.document = parsed
        indexBlocks()
        recomputeActiveBlocks()

        styler.update(theme: theme)
        let context = makeContext()

        let scope = styleScope(for: editedRange)
        styler.style(storage, document: parsed, lines: scope, context: context)
        styledLines = scope

        if ThemeManager.shared.focusMode {
            styler.applyFocusDimming(
                storage, document: parsed, lines: scope,
                activeParagraphID: context.activeParagraphID)
        }

        rebuildDecorations()
        rebuildOverlays(context: context)
    }

    /// Lines to restyle: everything on screen, plus whatever the edit touched.
    private func styleScope(for editedRange: NSRange?) -> Range<Int> {
        guard !parsed.lines.isEmpty else { return 0..<0 }
        let whole = 0..<parsed.lines.count
        guard let editedRange else { return whole }

        let length = (textView.string as NSString).length
        let clamped = NSRange(
            location: min(editedRange.location, length),
            length: min(editedRange.length, max(0, length - min(editedRange.location, length))))

        let edited = parsed.lineIndices(in: clamped)
        let visible = visibleLineRange()
        // A fence or a table can change how everything after it reads, so the
        // scope runs to the end of the block the edit landed in.
        let lower = min(edited.lowerBound, visible.lowerBound)
        let upper = max(blockEnd(after: edited.upperBound), visible.upperBound)
        return max(0, lower)..<min(upper, parsed.lines.count)
    }

    private func blockEnd(after line: Int) -> Int {
        guard line > 0, line - 1 < parsed.lines.count else { return line }
        let id = parsed.lines[line - 1].blockID
        var end = line
        while end < parsed.lines.count, parsed.lines[end].blockID == id { end += 1 }
        return end
    }

    /// Lines currently on screen, with a screenful of margin either side.
    private func visibleLineRange() -> Range<Int> {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              !parsed.lines.isEmpty else { return 0..<0 }

        let origin = textView.textContainerOrigin
        let visible = textView.visibleRect
            .insetBy(dx: 0, dy: -textView.visibleRect.height)
            .offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(
            forGlyphRange: glyphs, actualGlyphRange: nil)
        return parsed.lineIndices(in: characters)
    }

    /// Styles anything that has scrolled into view since the last pass.
    private func styleNewlyVisible() {
        guard let storage = textView.textStorage, !parsed.lines.isEmpty, !isStyling else { return }
        let visible = visibleLineRange()
        guard visible.lowerBound < styledLines.lowerBound
                || visible.upperBound > styledLines.upperBound else { return }

        isStyling = true
        defer { isStyling = false }

        let lower = min(visible.lowerBound, styledLines.lowerBound)
        let upper = max(visible.upperBound, styledLines.upperBound)
        let scope = lower..<upper
        let context = makeContext()
        styler.style(storage, document: parsed, lines: scope, context: context)
        if ThemeManager.shared.focusMode {
            styler.applyFocusDimming(
                storage, document: parsed, lines: scope,
                activeParagraphID: context.activeParagraphID)
        }
        styledLines = scope
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
                            quoteDepth: level))
                        runStart = runEnd
                    }
                }
            } else if case .thematicBreak = kind {
                for range in ranges {
                    result.append(BlockDecoration(
                        kind: .thematicBreak, lineRanges: [range], quoteDepth: 0))
                }
            } else {
                result.append(BlockDecoration(
                    kind: kind, lineRanges: ranges, quoteDepth: maxDepth))
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
        rebuildDecorations()
        rebuildOverlays(context: context)
    }

    // MARK: - Tables

    /// Line of the table the caret is in, or nil when it is somewhere else.
    private func caretTableLine() -> Int? {
        let caret = textView.selectedRange().location
        guard let index = parsed.lineIndex(at: caret),
              parsed.lines[index].kind.isTable else { return nil }
        return index
    }

    /// Whether two line numbers fall in the same table, which is what makes
    /// moving between rows different from leaving.
    private func sameTable(_ left: Int, _ right: Int?) -> Bool {
        guard let right, left < parsed.lines.count, right < parsed.lines.count else { return false }
        return parsed.lines[left].blockID == parsed.lines[right].blockID
    }

    /// Pads the cells of the table the caret has just left.
    ///
    /// Running it on the way out rather than on every keystroke is the whole
    /// trick: the columns are never rewritten under the cursor while a cell is
    /// half-typed, and by the time the table is read it is already square.
    private func formatTable(atLine line: Int) {
        guard !isFormatting, let storage = textView.textStorage else { return }
        let edits = TableFormatter.edits(forLine: line, in: parsed, text: storage.string as NSString)
        guard !edits.isEmpty else { return }

        let ranges = edits.map { NSValue(range: $0.range) }
        let strings = edits.map(\.text)
        guard textView.shouldChangeText(inRanges: ranges, replacementStrings: strings) else { return }

        isFormatting = true
        defer { isFormatting = false }

        // The caret has already moved out of the table, so it has to be carried
        // over whatever the padding added or removed above it.
        var selection = textView.selectedRange()
        var shift = 0
        for edit in edits where NSMaxRange(edit.range) <= selection.location {
            shift += (edit.text as NSString).length - edit.range.length
        }

        storage.beginEditing()
        for edit in edits.reversed() {
            storage.replaceCharacters(in: edit.range, with: edit.text)
        }
        storage.endEditing()
        textView.didChangeText()

        selection.location = max(0, min(storage.length, selection.location + shift))
        selection.length = min(selection.length, storage.length - selection.location)
        textView.setSelectedRange(selection)
    }

    /// Rect of the table the caret is in, in the given view's coordinates, so a
    /// control can be put on its corner. Nil when the caret is elsewhere.
    func caretTableRect(in target: NSView) -> NSRect? {
        guard let storage = textView.textStorage,
              let line = caretTableLine(),
              let table = TableFormatter.table(
                atLine: line, in: parsed, text: storage.string as NSString),
              let rect = textView.rect(for: table.range) else { return nil }
        return textView.convert(rect, to: target)
    }

    /// Opens the table editor on the table the caret is in.
    ///
    /// Returns false when there is no table there, so the Table command can fall
    /// back to inserting one.
    @discardableResult
    func editTableAtCaret() -> Bool {
        guard let storage = textView.textStorage,
              let line = caretTableLine(),
              let table = TableFormatter.table(
                atLine: line, in: parsed, text: storage.string as NSString) else { return false }

        // The popover points at the table, so it never covers what is being
        // edited unless there is nowhere else for it to go.
        let anchor = textView.rect(for: table.range) ?? textView.visibleRect

        var range = table.range
        let editor = TableEditorViewController(table: table) { [weak self] markdown in
            guard let self, let storage = self.textView.textStorage else { return }
            guard NSMaxRange(range) <= storage.length else { return }
            guard self.textView.shouldChangeText(in: range, replacementString: markdown) else {
                return
            }
            self.isFormatting = true
            storage.replaceCharacters(in: range, with: markdown)
            self.isFormatting = false
            self.textView.didChangeText()
            // The replacement is the table's new extent, and the next edit from
            // the panel has to overwrite that rather than the old one.
            range = NSRange(location: range.location, length: (markdown as NSString).length)
        }
        editor.preferredContentSize = editor.preferredSize

        let popover = NSPopover()
        popover.contentViewController = editor
        popover.behavior = .transient
        popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
        tablePopover = popover
        return true
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
        styleNewlyVisible()
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
        refresh(fullRestyle: false, editedRange: editedRange)
        onTextChange?()
    }
}

// MARK: - NSTextViewDelegate

extension EditorViewController: NSTextViewDelegate {

    func textViewDidChangeSelection(_ notification: Notification) {
        let table = caretTableLine()
        if let left = caretTableLineNumber, table == nil || !sameTable(left, table) {
            formatTable(atLine: left)
        }
        caretTableLineNumber = caretTableLine()

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

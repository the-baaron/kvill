import AppKit
import UniformTypeIdentifiers

/// Something drawn into space the styler reserved by kerning the underlying
/// characters down. The document text is never altered to make room.
enum TextOverlay {
    /// A task list checkbox, in place of `[ ]` or `[x]`.
    case checkbox(NSRange, TaskState)
    /// A bullet dot, in place of a `-`, `*` or `+` in the gutter.
    case bullet(NSRange)
    /// A callout's title, in place of the raw `[!NOTE]`.
    case calloutTitle(NSRange, CalloutKind?)
    /// A picture, drawn under the Markdown line that references it.
    case image(NSRange, URL, NSSize)
}

/// A run of lines sharing one background treatment.
struct BlockDecoration {
    let kind: DecorationKind
    /// Character range of each line in the block, in order.
    let lineRanges: [NSRange]
    /// Deepest `>` nesting in the block, for drawing quote bars.
    let quoteDepth: Int
}

/// The text view itself. It owns the drawing of everything that sits *behind*
/// the text: code block panels, callout tints, quote bars.
final class EditorTextView: NSTextView {

    var theme: Theme = ThemeManager.shared.theme {
        didSet { applyTheme() }
    }

    var decorations: [BlockDecoration] = [] {
        didSet { needsDisplay = true }
    }

    /// Checkboxes, bullets and callout titles painted over collapsed text.
    var overlays: [TextOverlay] = [] {
        didSet { needsDisplay = true }
    }

    /// Latest parse, used for hit testing links and checkboxes.
    var document: ParsedDocument?

    /// Called when the user clicks a task checkbox.
    var onToggleTask: ((NSRange) -> Void)?

    /// Called when an image is dropped, with the character index to insert at.
    /// Returning true means the drop was handled here.
    var onImageDrop: ((NSDraggingInfo, Int) -> Bool)?

    /// A folder was dropped on the page, which asks for the sidebar.
    var onFolderDrop: ((URL) -> Void)?

    /// A text file dropped on the page, which opens it beside this one.
    var onDocumentDrop: ((URL) -> Void)?

    /// Called when a click-drag selection finishes, so the formatting bar can
    /// appear once rather than following the pointer during the drag.
    var onSelectionGestureEnded: (() -> Void)?

    /// True while a mouse-driven selection is in progress.
    private(set) var isSelectingWithMouse = false

    /// Intercepts AppKit's scroll-to-caret. Returning true means the handler has
    /// positioned the view itself, which is how typewriter mode stops fighting
    /// the text view's own scrolling on every keystroke.
    var typewriterScroll: ((NSRange) -> Bool)?

    override func scrollRangeToVisible(_ range: NSRange) {
        if typewriterScroll?(range) == true { return }
        super.scrollRangeToVisible(range)
    }

    /// The line fragment containing `index`, in this view's coordinates.
    ///
    /// This is deliberately the *fragment* rather than the glyph bounds: it does
    /// not move while typing along a line, so typewriter scrolling has a stable
    /// target and only moves when the caret actually changes line.
    func lineFragmentRect(atCharacterIndex index: Int) -> NSRect? {
        guard let layoutManager, let storage = textStorage else { return nil }
        let origin = textContainerOrigin

        // Caret past the last character, on the empty line a trailing newline makes.
        if index >= storage.length, layoutManager.extraLineFragmentTextContainer != nil {
            var rect = layoutManager.extraLineFragmentRect
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            return rect
        }
        guard layoutManager.numberOfGlyphs > 0 else { return nil }

        let character = min(max(index, 0), max(0, storage.length - 1))
        let glyph = min(
            layoutManager.glyphIndexForCharacter(at: character),
            layoutManager.numberOfGlyphs - 1)
        var rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }

    // MARK: - Setup

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        commonSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonSetup()
    }

    private func commonSetup() {
        drawsBackground = false
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        smartInsertDeleteEnabled = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0

        registerForDraggedTypes([
            .fileURL, .png, .tiff,
            NSPasteboard.PasteboardType(UTType.image.identifier),
        ])
        applyTheme()
    }

    // MARK: - Dropping images

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if accepts(sender) { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if accepts(sender) { return .copy }
        return super.draggingUpdated(sender)
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        ImageDrop.canAccept(sender)
            || Self.folder(in: sender) != nil
            || Self.document(in: sender) != nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // A folder dropped on the page is a request for the sidebar, not for its
        // path to be typed into the document. Without this the drop fell through
        // to NSTextView, which inserted the path as text, and the only route to
        // the tree was File > Open Folder.
        if let folder = Self.folder(in: sender) {
            onFolderDrop?(folder)
            return true
        }
        // A document dropped on the page is a request to read it, not to type
        // its path. Without this it fell through to NSTextView and inserted
        // "/Users/.../notes.md" into whatever was being written.
        if let document = Self.document(in: sender) {
            onDocumentDrop?(document)
            return true
        }
        if ImageDrop.canAccept(sender) {
            let point = convert(sender.draggingLocation, from: nil)
            let index = characterIndexForInsertion(at: point)
            if onImageDrop?(sender, index) == true { return true }
        }
        return super.performDragOperation(sender)
    }

    /// The one text file being dragged, if that is what this is.
    ///
    /// Images are not included: a picture dropped on a page is a picture to put
    /// in it, which is what `ImageDrop` is for, and that behaviour predates this
    /// one. Anything else that reads as text opens beside.
    static func document(in info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard urls.count == 1, let url = urls.first else { return nil }
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true else {
            return nil
        }
        guard !ImageDrop.imageURLs(in: info.draggingPasteboard).contains(url) else { return nil }
        return KvillDocumentController.isReadableAsText(url) ? url : nil
    }

    /// The one folder being dragged, if that is what this is.
    ///
    /// A drop of several things, or of a folder alongside a file, is left to the
    /// existing paths rather than guessed at.
    private static func folder(in info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard urls.count == 1, let url = urls.first,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return nil }
        return url
    }

    private func applyTheme() {
        insertionPointColor = theme.colors.cursor
        selectedTextAttributes = [
            .backgroundColor: theme.colors.selection
        ]
        font = theme.body
        appearance = theme.colors.appearance

        // The caret on an empty line is placed from the typing attributes, not
        // from any styled character, so these need the same indent the styler
        // gives every other line. Without it the caret jumps to the far left of
        // the gutter the moment you open a blank line.
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = theme.metrics.gutter
        style.headIndent = theme.metrics.gutter
        style.minimumLineHeight = theme.metrics.lineHeight
        style.maximumLineHeight = theme.metrics.lineHeight
        style.lineBreakMode = .byWordWrapping
        defaultParagraphStyle = style

        typingAttributes = [
            .font: theme.body,
            .foregroundColor: theme.colors.text,
            .paragraphStyle: style,
        ]
        needsDisplay = true
    }

    // MARK: - Drawing

    /// Stays where the reader left it when the text reflows.
    ///
    /// `NSTextView` scrolls to the insertion point from inside its private
    /// `_setFrameSize:forceScroll:`, and a width change is what triggers it.
    /// Every reflow therefore moved the page: turning the index on scrolled a
    /// freshly opened document 68 points down, which read as the page having
    /// been left half way through.
    ///
    /// Only on a width change. A height change is the document growing as
    /// someone types, and following the caret there is exactly right.
    override func setFrameSize(_ newSize: NSSize) {
        let reflowed = abs(newSize.width - frame.width) > 0.5
        let clip = enclosingScrollView?.contentView
        let origin = clip?.bounds.origin
        super.setFrameSize(newSize)
        guard reflowed, let clip, let origin, clip.bounds.origin != origin else { return }
        clip.setBoundsOrigin(origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    /// Stays where the reader left it when the window changes size.
    ///
    /// `NSTextView` scrolls to the insertion point at the end of a live resize,
    /// through a private `_setFrameSize:forceScroll:`. Opening a folder slides
    /// the sidebar in, which is a live resize of this view, so a document you
    /// had just opened jumped 62 points down the moment the sidebar arrived.
    /// Entering full screen did the same. Caught by watching the clip view's
    /// origin and printing who moved it, because nothing in this app was
    /// scrolling anything.
    ///
    /// The caret is not what someone is looking at while they resize a window.
    /// Where they had scrolled to is.
    ///
    /// Not covered by a check, deliberately. AppKit only scrolls from inside
    /// its own `_setFrameSize:forceScroll:`, which nothing here can bring about
    /// on demand: a synthetic resize scrolls before this override is reached
    /// and so passes whether the override exists or not. Verified instead by
    /// measuring the clip view's origin through a real sidebar animation and a
    /// real full screen transition, where it went from 62 to 0 and stayed.
    override func viewDidEndLiveResize() {
        let clip = enclosingScrollView?.contentView
        let origin = clip?.bounds.origin
        super.viewDidEndLiveResize()
        guard let clip, let origin, clip.bounds.origin != origin else { return }
        clip.setBoundsOrigin(origin)
        enclosingScrollView?.reflectScrolledClipView(clip)
    }

    override func draw(_ dirtyRect: NSRect) {
        fillPage(dirtyRect)
        drawDecorations(in: dirtyRect)
        drawChangeFlash(in: dirtyRect)
        super.draw(dirtyRect)
        drawOverlays(in: dirtyRect)
        drawPlaceholder()
    }

    // MARK: - Marking what something else changed

    /// How long a change stays lit, and how long it takes to go.
    ///
    /// Held at full first so the eye can land on it, then faded. A mark that
    /// starts fading immediately is gone before you have looked up.
    static let flashHold: TimeInterval = 0.5
    static let flashFade: TimeInterval = 0.7

    private var flashRanges: [NSRange] = []
    private var flashStartedAt: Date?
    private var flashTimer: Timer?

    /// Lights the parts of the page something else just rewrote.
    ///
    /// Drawn rather than applied as an attribute. A temporary attribute would go
    /// through the layout manager on every frame of the fade, and this runs
    /// while a file is being rewritten underneath the window, which is the worst
    /// possible moment to be making layout do more work.
    func flashChanges(_ ranges: [NSRange]) {
        flashTimer?.invalidate()
        flashRanges = ranges
        guard !ranges.isEmpty else {
            flashTimer = nil
            flashStartedAt = nil
            needsDisplay = true
            return
        }
        flashStartedAt = Date()
        needsDisplay = true

        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            guard let started = self.flashStartedAt,
                  Date().timeIntervalSince(started) < Self.flashHold + Self.flashFade else {
                timer.invalidate()
                self.flashTimer = nil
                self.flashStartedAt = nil
                self.flashRanges = []
                self.needsDisplay = true
                return
            }
            self.needsDisplay = true
        }
        flashTimer = timer
        // Common modes, or the fade freezes mid-way while a menu is open or the
        // page is being scrolled, which is exactly when a file tends to change
        // underneath you.
        RunLoop.main.add(timer, forMode: .common)
    }

    /// How lit the change is right now, from 1 down to 0.
    var flashStrength: CGFloat {
        guard let started = flashStartedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(started)
        if elapsed <= Self.flashHold { return 1 }
        let faded = (elapsed - Self.flashHold) / Self.flashFade
        return CGFloat(max(0, 1 - faded))
    }

    /// The ranges currently lit, for the self test.
    var flashRangesForTest: [NSRange] { flashRanges }

    private func drawChangeFlash(in dirtyRect: NSRect) {
        guard !flashRanges.isEmpty else { return }
        let strength = flashStrength
        guard strength > 0 else { return }

        let colors = theme.colors
        colors.accent.withAlphaComponent(0.22 * strength).setFill()
        for range in flashRanges {
            for box in flashBoxes(for: range) where box.intersects(dirtyRect) {
                NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
            }
        }
    }

    /// One box per line the range covers, so a rewritten paragraph is marked
    /// line by line rather than as one rectangle swallowing the margins.
    private func flashBoxes(for range: NSRange) -> [NSRect] {
        guard let layoutManager, let textContainer, let storage = textStorage else { return [] }
        let length = storage.length
        guard length > 0, range.location >= 0, range.location <= length else { return [] }

        let origin = textContainerOrigin
        // A pure deletion has nothing to light, so a sliver marks the join.
        if range.length == 0 {
            let at = min(range.location, max(0, length - 1))
            let glyph = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: at, length: 1), actualCharacterRange: nil)
            guard glyph.length > 0 else { return [] }
            var box = layoutManager.boundingRect(forGlyphRange: glyph, in: textContainer)
            box.origin.x += origin.x
            box.origin.y += origin.y
            return [NSRect(x: box.minX - 1, y: box.minY, width: 2, height: box.height)]
        }

        let end = min(NSMaxRange(range), length)
        guard end > range.location else { return [] }
        let safe = NSRange(location: range.location, length: end - range.location)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: safe, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return [] }

        var boxes: [NSRect] = []
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            _, _, container, lineGlyphRange, _ in
            // Only the part of the line the change actually covers, so an edit
            // to the end of a paragraph does not light the whole paragraph.
            let covered = NSIntersectionRange(lineGlyphRange, glyphRange)
            guard covered.length > 0 else { return }
            var box = layoutManager.boundingRect(forGlyphRange: covered, in: container)
            box.origin.x += origin.x
            box.origin.y += origin.y
            boxes.append(box.insetBy(dx: -2, dy: -1))
        }
        return boxes
    }

    /// Draws a page of the document into the current graphics context without
    /// going through `NSView.draw`.
    ///
    /// `draw(_:)` consults the view's `visibleRect`, which is unreliable for a
    /// window that was never put on screen, so the headless PNG renderer would
    /// get a blank or partial page depending on the canvas size. Going straight
    /// to the layout manager is deterministic.
    func renderPage(_ rect: NSRect, opaqueBackground: Bool = false) {
        if opaqueBackground {
            theme.colors.background.setFill()
            rect.fill()
        } else {
            fillPage(rect)
        }
        drawDecorations(in: rect)

        if let layoutManager, let textContainer {
            let origin = textContainerOrigin
            // `glyphRange(forBoundingRect:)` works in the container's coordinates,
            // which are the view's shifted by the container origin.
            let containerRect = rect.offsetBy(dx: -origin.x, dy: -origin.y)
            let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
            layoutManager.drawBackground(forGlyphRange: glyphs, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        }

        drawOverlays(in: rect)
        drawPlaceholder()
    }

    /// Paints the page colour, or nothing at all for a translucent palette.
    ///
    /// A glass page is built the way every other translucent macOS window builds
    /// one: a material behind the window, a tint over it, and a text view that
    /// paints no background whatsoever. Filling here with a half-transparent
    /// colour instead means glyphs are antialiased against partial alpha, which
    /// is what made the page look wrong.
    private func fillPage(_ rect: NSRect) {
        theme.colors.background.setFill()
        rect.fill()
    }

    /// What an empty document says, so a blank window is not a dead end.
    ///
    /// Drawn rather than inserted: the document is genuinely empty, so nothing
    /// has to be taken back out before the first keystroke, and it cannot end up
    /// saved to the file.
    /// The placeholder text, or nil when there is a document to show.
    var placeholderForTest: String? {
        textStorage?.length == 0 ? Self.placeholder : nil
    }

    private static let placeholder = "Start typing, or press / to insert"


    private func drawPlaceholder() {
        guard textStorage?.length == 0, let layoutManager,
              layoutManager.extraLineFragmentTextContainer != nil else { return }

        // Drawn into the caret's own line fragment with the caret's own
        // attributes, so it sits where the first character will, whatever the
        // text size. The one addition is the baseline lift the styler gives
        // every line: forcing a line height taller than the font's own puts the
        // extra space above the glyphs, and half of it has to be given back.
        var rect = layoutManager.extraLineFragmentRect
        let origin = textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y

        var attributes = typingAttributes
        attributes[.foregroundColor] = theme.colors.textSecondary.withAlpha(0.45)
        let natural = ceil(theme.body.ascender + abs(theme.body.descender) + theme.body.leading)
        let surplus = theme.metrics.lineHeight - natural
        if surplus > 0.5 { attributes[.baselineOffset] = surplus / 2 }

        NSAttributedString(string: Self.placeholder, attributes: attributes)
            .draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
    }

    private func drawOverlays(in dirtyRect: NSRect) {
        guard !overlays.isEmpty else { return }
        for overlay in overlays {
            switch overlay {
            case .checkbox(let range, let state):
                drawCheckbox(range: range, state: state, dirtyRect: dirtyRect)
            case .bullet(let range):
                drawBullet(range: range, dirtyRect: dirtyRect)
            case .calloutTitle(let range, let kind):
                drawCalloutTitle(range: range, kind: kind, dirtyRect: dirtyRect)
            case .image(let range, let url, let size):
                drawImage(range: range, url: url, size: size, dirtyRect: dirtyRect)
            }
        }
    }

    /// Where a mark drawn next to text should be centred.
    ///
    /// Not the middle of the line box: that sits low, because a line reserves
    /// room under the baseline for descenders and most words have none. The
    /// middle of a capital letter is what the eye reads as the centre, so marks
    /// are hung off the baseline instead.
    private func opticalCentre(of slot: NSRect, at location: Int) -> CGFloat {
        guard let layoutManager, layoutManager.numberOfGlyphs > 0 else { return slot.midY }
        let glyph = layoutManager.glyphIndexForCharacter(at: location)
        guard glyph < layoutManager.numberOfGlyphs else { return slot.midY }
        let baseline = layoutManager.location(forGlyphAt: glyph).y
        return slot.minY + baseline - theme.body.capHeight / 2
    }

    /// Paints a checkbox into the blank square the styler reserved for it.
    ///
    /// This view is flipped, so y grows downward: the middle of the tick is the
    /// point with the largest y, not the smallest.
    private func drawCheckbox(range: NSRange, state: TaskState, dirtyRect: NSRect) {
        guard let slot = rect(for: range) else { return }
        let side = theme.metrics.checkboxSize
        let colors = theme.colors

        let centre = opticalCentre(of: slot, at: range.location)
        let box = NSRect(
            x: slot.minX, y: centre - side / 2, width: side, height: side
        ).insetBy(dx: 0.75, dy: 0.75)
        guard box.intersects(dirtyRect) else { return }

        let path = NSBezierPath(roundedRect: box, xRadius: side * 0.3, yRadius: side * 0.3)

        switch state {
        case .open:
            colors.marker.withAlpha(0.8).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        case .done:
            colors.accent.setFill()
            path.fill()

            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: box.minX + side * 0.23, y: box.midY - side * 0.02))
            tick.line(to: NSPoint(x: box.minX + side * 0.42, y: box.midY + side * 0.19))
            tick.line(to: NSPoint(x: box.minX + side * 0.76, y: box.midY - side * 0.22))
            tick.lineWidth = max(1.5, side * 0.14)
            tick.lineCapStyle = .round
            tick.lineJoinStyle = .round
            colors.background.setStroke()
            tick.stroke()
        }
    }

    private func drawBullet(range: NSRange, dirtyRect: NSRect) {
        guard let slot = rect(for: range), slot.intersects(dirtyRect) else { return }
        let diameter = theme.metrics.base * 0.30
        let dot = NSRect(
            x: slot.maxX - diameter,
            y: opticalCentre(of: slot, at: range.location) - diameter / 2,
            width: diameter, height: diameter)
        theme.colors.marker.withAlpha(0.95).setFill()
        NSBezierPath(ovalIn: dot).fill()
    }

    private func drawCalloutTitle(range: NSRange, kind: CalloutKind?, dirtyRect: NSRect) {
        guard let slot = rect(for: range), slot.intersects(dirtyRect) else { return }
        let palette = theme.callout(kind)
        let title = kind?.title ?? "Note"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: theme.calloutTitle,
            .foregroundColor: palette.accent,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: slot.minX, y: slot.midY - size.height / 2),
            withAttributes: attributes)
    }

    /// Where a picture sits: in the paragraph spacing directly above its caption.
    func imageFrame(caption: NSRect, size: NSSize) -> NSRect {
        let metrics = theme.metrics
        let columnLeft = textContainerOrigin.x + metrics.gutter
        return NSRect(
            x: columnLeft + max(0, (metrics.measure - size.width) / 2),
            y: caption.minY - metrics.base * 0.45 - size.height,
            width: size.width,
            height: size.height)
    }

    /// The picture for a point, if the point lands on one.
    func imageOverlay(at point: NSPoint) -> (range: NSRange, frame: NSRect)? {
        for overlay in overlays {
            guard case .image(let range, _, let size) = overlay,
                  let slot = rect(for: range) else { continue }
            let frame = imageFrame(caption: slot, size: size)
            if frame.contains(point) { return (range, frame) }
        }
        return nil
    }

    /// Draws an embedded image above its caption.
    private func drawImage(range: NSRange, url: URL, size: NSSize, dirtyRect: NSRect) {
        guard let slot = rect(for: range),
              let image = ImageStore.shared.image(at: url) else { return }

        let frame = imageFrame(caption: slot, size: size)
        guard frame.intersects(dirtyRect) else { return }

        let path = NSBezierPath(roundedRect: frame, xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        // A text view is flipped, and the plain `draw(in:)` does not account for
        // that, which renders every image upside down. `respectFlipped` does.
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: frame, from: .zero, operation: .sourceOver, fraction: 1,
            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        NSGraphicsContext.restoreGraphicsState()

        // A selected image gets a ring rather than a text highlight behind it.
        let selection = selectedRange()
        let selected = selection.length > 0
            && NSIntersectionRange(selection, range).length == range.length
        if selected {
            theme.colors.accent.setStroke()
            let ring = NSBezierPath(
                roundedRect: frame.insetBy(dx: -2.5, dy: -2.5), xRadius: 9, yRadius: 9)
            ring.lineWidth = 2.5
            ring.stroke()
        } else {
            theme.colors.rule.withAlpha(0.6).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    /// The panels painted on the last drawing pass.
    ///
    /// Recorded as they are drawn rather than recomputed for the checks. A check
    /// that works the geometry out a second time is only ever agreeing with its
    /// own copy of the sum, which is how the listing checks once reported 2619
    /// characters while Apple was receiving 80.
    private(set) var drawnPanels: [NSRect] = []

    private func drawDecorations(in dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let metrics = theme.metrics
        let origin = textContainerOrigin
        let columnLeft = origin.x + metrics.gutter
        // Clamped, because `measure` is the column width the typography preset
        // asks for and takes no account of the window: in a narrow window the
        // text rewraps to what actually fits, but a panel drawn to `measure`
        // kept its full width and ran off the right edge.
        //
        // Clamped to the window's own margin rather than to where the text ends.
        // Clamping to the text's edge left a callout's last words sitting on its
        // own border, padded on the left and not on the right. The text inset
        // keeps enough room for this to sit outside it.
        let pageRight = bounds.width - EditorViewController.panelMargin
        let columnRight = min(columnLeft + metrics.measure, pageRight)

        /// A panel behind a block, never wider than the page.
        func panel(_ block: NSRect, pad: CGFloat, dy: CGFloat) -> NSRect {
            let left = columnLeft - pad
            let right = min(columnRight + pad, pageRight)
            let rect = NSRect(
                x: left, y: block.minY - dy,
                width: max(0, right - left), height: block.height + dy * 2)
            drawnPanels.append(rect)
            return rect
        }
        drawnPanels.removeAll(keepingCapacity: true)

        context.saveGState()
        defer { context.restoreGState() }

        for decoration in decorations {
            guard let bounds = blockRect(for: decoration.lineRanges) else { continue }
            guard bounds.intersects(dirtyRect.insetBy(dx: 0, dy: -200)) else { continue }

            switch decoration.kind {
            case .codeBlock:
                let box = panel(bounds, pad: 14, dy: 6)
                fill(box, radius: 8, color: theme.colors.codeBackground,
                     stroke: theme.colors.codeBorder)

            case .table:
                let box = panel(bounds, pad: 14, dy: 6)
                fill(box, radius: 8, color: theme.colors.codeBackground,
                     stroke: theme.colors.tableBorder.withAlpha(0.5))

            case .frontMatter:
                let box = panel(bounds, pad: 14, dy: 5)
                fill(box, radius: 8, color: theme.colors.backgroundElevated,
                     stroke: theme.colors.rule)

            case .callout(let kind):
                let palette = theme.callout(kind)
                let box = panel(bounds, pad: 18, dy: 7)
                fill(box, radius: 9, color: palette.background, stroke: palette.accent.withAlpha(0.28))

                // Accent bar down the left edge, with the box's corner radius.
                let bar = NSRect(x: box.minX, y: box.minY, width: 3.5, height: box.height)
                let barPath = NSBezierPath(
                    roundedRect: NSRect(x: box.minX, y: box.minY, width: 12, height: box.height),
                    xRadius: 9, yRadius: 9)
                context.saveGState()
                NSBezierPath(rect: bar).addClip()
                palette.accent.setFill()
                barPath.fill()
                context.restoreGState()

                drawCalloutIcon(kind, palette: palette, box: box, firstLine: decoration.lineRanges.first)

            case .blockquote(let depth):
                theme.colors.quoteBar.setFill()
                for level in 0..<max(depth, 1) {
                    let x = columnLeft + CGFloat(level) * metrics.indentStep
                    let bar = NSRect(x: x, y: bounds.minY, width: 3, height: bounds.height)
                    NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
                }


            case .thematicBreak:
                theme.colors.rule.setStroke()
                let y = (bounds.minY + bounds.maxY) / 2
                let path = NSBezierPath()
                path.move(to: NSPoint(x: columnLeft, y: y))
                path.line(to: NSPoint(x: columnRight, y: y))
                path.lineWidth = 1
                path.stroke()
            }
        }
    }

    private func drawCalloutIcon(
        _ kind: CalloutKind?, palette: CalloutColors, box: NSRect, firstLine: NSRange?
    ) {
        guard let kind, let firstLine, let lineRect = rect(for: firstLine) else { return }
        let config = NSImage.SymbolConfiguration(
            pointSize: theme.metrics.base * 0.78, weight: .semibold)
        guard let image = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: kind.title)?
            .withSymbolConfiguration(config) else { return }

        let size = image.size
        let point = NSPoint(
            x: box.minX + 9,
            y: lineRect.midY - size.height / 2)
        let tinted = NSImage(size: size, flipped: false) { rect in
            palette.accent.set()
            image.draw(in: rect)
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(origin: point, size: size))
    }

    private func fill(_ rect: NSRect, radius: CGFloat, color: NSColor, stroke: NSColor?) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.setFill()
        path.fill()
        if let stroke {
            stroke.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    // MARK: - Geometry

    /// Bounding rect of a character range in view coordinates.
    /// Bounding rect of a character range, or nil if the range is not one this
    /// document actually has.
    ///
    /// Decorations and overlays are built from a parse and drawn later. A
    /// deletion between those two moments leaves ranges pointing past the end of
    /// the text, and asking the layout manager for a rect outside the string
    /// raises. AppKit turns an exception raised during drawing into a crash, so
    /// this has to reject a stale range rather than clamp it into something that
    /// merely looks plausible.
    func rect(for range: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer, let storage = textStorage else { return nil }

        let length = storage.length
        guard length > 0, range.location >= 0, range.location < length else { return nil }

        let end = min(NSMaxRange(range), length)
        guard end > range.location else { return nil }

        let safe = NSRange(location: range.location, length: end - range.location)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: safe, actualCharacterRange: nil)
        guard glyphRange.length > 0 || glyphRange.location < layoutManager.numberOfGlyphs else {
            return nil
        }

        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let origin = textContainerOrigin
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }

    func blockRect(for ranges: [NSRange]) -> NSRect? {
        var result: NSRect?
        for range in ranges {
            guard let rect = rect(for: range) else { continue }
            result = result.map { $0.union(rect) } ?? rect
        }
        return result
    }

    // MARK: - Interaction

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Clicking a picture selects it, rather than dropping a caret into the
        // Markdown that describes it.
        if let hit = imageOverlay(at: point) {
            setSelectedRange(hit.range)
            needsDisplay = true
            onSelectionGestureEnded?()
            return
        }

        let index = characterIndexForInsertion(at: point)

        if let document, let lineIndex = document.lineIndex(at: index) {
            let line = document.lines[lineIndex]

            // Clicking the checkbox of a task item toggles it.
            if case .listItem(_, let task) = line.kind, task != nil {
                for token in line.inlines {
                    if case .taskMarker = token.kind, NSLocationInRange(index, token.range) {
                        onToggleTask?(token.range)
                        return
                    }
                }
            }

            // Command-click opens links, matching the rest of macOS.
            if event.modifierFlags.contains(.command) {
                if let url = url(at: index, line: line) {
                    NSWorkspace.shared.open(url)
                    return
                }
            }
        }

        // NSTextView tracks the drag inside its own event loop, so this returns
        // only once the mouse is released.
        isSelectingWithMouse = true
        super.mouseDown(with: event)
        isSelectingWithMouse = false
        onSelectionGestureEnded?()
    }

    /// Turns a destination into a URL, looking it up in the document's reference
    /// definitions when it is a label rather than an address.
    private func resolve(_ destination: String?, fallbackLabel: String) -> URL? {
        if let destination, destination.contains(":") || destination.hasPrefix("/") {
            return URL(string: destination)
        }
        let label = (destination ?? fallbackLabel).lowercased()
        if let target = document?.linkDefinitions[label] {
            return URL(string: target)
        }
        return destination.flatMap { URL(string: $0) }
    }

    private func url(at index: Int, line: MDLine) -> URL? {
        guard let storage = textStorage else { return nil }
        let text = storage.string as NSString

        for token in line.inlines {
            guard NSLocationInRange(index, token.range) else { continue }
            switch token.kind {
            case .autolink:
                return URL(string: text.substring(with: token.range))
            case .linkText, .linkURL:
                // Find the destination token that belongs to this link.
                if let destination = line.inlines.first(where: {
                    if case .linkURL = $0.kind { return $0.range.location >= token.range.location }
                    return false
                }) {
                    let raw = text.substring(with: destination.range)
                    let trimmed = raw.split(separator: " ").first.map(String.init) ?? raw
                    return resolve(trimmed, fallbackLabel: text.substring(with: token.range))
                }
                // A shortcut reference has no destination token: `[label]` alone.
                return resolve(nil, fallbackLabel: text.substring(with: token.range))
            default:
                break
            }
        }
        return nil
    }

}

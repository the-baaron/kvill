import AppKit

/// Turns a `ParsedDocument` into text attributes.
///
/// The interesting part is the gutter. Every line's content is laid out on the
/// same x position (`contentX`), and its syntax marker is pushed into the space
/// to the left of it, right-aligned so that `#`, `##` and `######` all finish on
/// the same column. That is done with two paragraph indents and one kerned space:
///
///     firstLineHeadIndent = contentX - gap - markerWidth   (where the marker starts)
///     headIndent          = contentX                       (where wrapped lines start)
///     kern on last gap char = gap - naturalGapWidth        (pins content to contentX)
///
/// Nothing is inserted or removed from the document to achieve this, so the text
/// on disk is exactly what the user typed.
final class MarkdownStyler {

    private(set) var theme: Theme

    /// Folder the document lives in, used to resolve relative image paths.
    var baseURL: URL?

    private var markerWidths: [String: CGFloat] = [:]
    private var paragraphStyles: [String: NSParagraphStyle] = [:]
    private var traitFonts: [String: NSFont] = [:]
    private var lineHeights: [String: CGFloat] = [:]

    /// Table blocks whose header row has nothing in it.
    private(set) var emptyHeaderBlocks: Set<Int> = []


    init(theme: Theme) {
        self.theme = theme
    }

    func update(theme: Theme) {
        guard theme.identifier != self.theme.identifier else { return }
        self.theme = theme
        markerWidths.removeAll()
        paragraphStyles.removeAll()
        traitFonts.removeAll()
        lineHeights.removeAll()
    }

    struct Context {
        /// Blocks the selection touches. Markers are revealed only inside these,
        /// so a heading reads as a heading until you put the caret in it.
        var activeBlockIDs: Set<Int> = []
        /// Paragraph the caret sits in. Focus mode lights this and dims the rest.
        var activeParagraphID: Int?
        var focusMode: Bool = false
        /// Keeps markers dimly visible everywhere instead of only in the active
        /// element. Off by default.
        var alwaysShowMarkers: Bool = false
    }

    // MARK: - Entry point

    func style(
        _ storage: NSTextStorage,
        document: ParsedDocument,
        lines lineRange: Range<Int>,
        context: Context
    ) {
        guard !document.lines.isEmpty else { return }
        let text = storage.string as NSString
        let clamped = lineRange.clamped(to: 0..<document.lines.count)
        guard !clamped.isEmpty else { return }

        storage.beginEditing()
        for index in clamped {
            styleLine(document.lines[index], index: index, text: text, storage: storage, context: context)
        }
        storage.endEditing()
    }

    // MARK: - Tables

    private struct TableLayout {
        /// Widest trimmed cell per column, at `fontSize`.
        var columns: [CGFloat]
        /// Point size after shrinking the table to fit the measure.
        var fontSize: CGFloat
        /// False when the table overflows even at the smallest size, in which
        /// case rows wrap and the grid is abandoned rather than left broken.
        var fits: Bool
    }

    private var tableLayouts: [Int: TableLayout] = [:]

    /// Padding either side of a cell's text, as a share of the table's font size.
    private func cellPadding(_ fontSize: CGFloat) -> CGFloat { fontSize * 0.55 }

    /// The smallest a table is allowed to shrink before it is left to wrap.
    private static let minimumTableScale: CGFloat = 0.58

    /// Measures every table so its cells can be kerned onto a common grid, and
    /// shrinks any table that would otherwise be too wide for the column.
    ///
    /// Fitting matters more than it looks: a row is one paragraph, so the moment
    /// it wraps the kerned grid is meaningless. Shrinking to fit keeps rows on
    /// one line, which is what keeps the table a table.
    func prepareTables(_ document: ParsedDocument, text: NSString) {
        tableLayouts.removeAll(keepingCapacity: true)
        emptyHeaderBlocks.removeAll(keepingCapacity: true)

        let available = theme.metrics.measure
        let base = theme.metrics.base

        var index = 0
        while index < document.lines.count {
            guard document.lines[index].kind.isTable else {
                index += 1
                continue
            }
            let blockID = document.lines[index].blockID
            var end = index
            while end < document.lines.count,
                  document.lines[end].blockID == blockID,
                  document.lines[end].kind.isTable {
                end += 1
            }
            let rows = Array(document.lines[index..<end])

            var size = base
            var columns = measureColumns(rows, text: text, size: size)
            var total = tableWidth(columns, size: size)

            // Font metrics are not linear in point size, so one ratio rarely
            // lands inside the measure. Aim a little under it and iterate, or
            // the table ends up a hair too wide and loses its grid for nothing.
            let target = available * 0.97
            var attempts = 0
            while total > target, attempts < 5 {
                let next = max(base * Self.minimumTableScale, size * target / total)
                if next >= size { break }  // already at the floor
                size = next
                columns = measureColumns(rows, text: text, size: size)
                total = tableWidth(columns, size: size)
                attempts += 1
            }

            let fits = total <= available
            // A table that will not fit even at the smallest size gets no grid,
            // so it drops back to plain monospace source with its pipes showing.
            // Half a grid is worse than none.
            tableLayouts[blockID] = TableLayout(
                columns: columns,
                fontSize: fits ? size : base * 0.86,
                fits: fits)

            let headerCells = cells(text, in: rows[0].contentRange)
            if headerCells.allSatisfy({
                text.substring(with: $0).trimmingCharacters(in: .whitespaces).isEmpty
            }) {
                emptyHeaderBlocks.insert(blockID)
            }

            index = end
        }
    }

    private func measureColumns(_ rows: [MDLine], text: NSString, size: CGFloat) -> [CGFloat] {
        var widths: [CGFloat] = []
        for line in rows where line.kind != .tableDelimiter {
            let font = tableFont(line.kind, size: size)
            for (column, cell) in cells(text, in: line.contentRange).enumerated() {
                let trimmed = text.substring(with: cell).trimmingCharacters(in: .whitespaces)
                let value = trimmed.isEmpty ? 0 : width(of: trimmed, font: font)
                if column < widths.count {
                    widths[column] = max(widths[column], value)
                } else {
                    widths.append(value)
                }
            }
        }
        return widths
    }

    private func tableWidth(_ columns: [CGFloat], size: CGFloat) -> CGFloat {
        let padding = cellPadding(size)
        return columns.reduce(0) { $0 + $1 + padding * 2 }
    }

    /// The runs between the pipes of a table row, excluding the pipes themselves
    /// and anything outside the outer pair.
    private func cells(_ text: NSString, in range: NSRange) -> [NSRange] {
        let pipes = pipePositions(text, in: range)
        guard pipes.count >= 2 else { return [] }
        return (0..<(pipes.count - 1)).map { index in
            NSRange(location: pipes[index] + 1, length: pipes[index + 1] - pipes[index] - 1)
        }
    }

    private func pipePositions(_ text: NSString, in range: NSRange) -> [Int] {
        var result: [Int] = []
        var index = range.location
        let end = NSMaxRange(range)
        while index < end {
            if text.character(at: index) == 124,  // '|'
               !MarkdownParser.isEscaped(text, index, from: range.location) {
                result.append(index)
            }
            index += 1
        }
        return result
    }

    /// Tables are set in the reading face, not a monospace one. The columns line
    /// up because they are kerned to measured widths, so nothing is gained by
    /// making every glyph the same width, and a proportional table reads far
    /// better next to proportional prose.
    private func tableFont(_ kind: BlockKind, size: CGFloat) -> NSFont {
        kind == .tableHeader
            ? FontBuilder.font(theme.preset.bodyFamily, size: size, weight: .semibold)
            : FontBuilder.font(theme.preset.bodyFamily, size: size)
    }

    func tableFits(blockID: Int) -> Bool {
        tableLayouts[blockID]?.fits ?? true
    }

    private func tableFontSize(for line: MDLine) -> CGFloat {
        tableLayouts[line.blockID]?.fontSize ?? theme.metrics.base
    }

    /// The face a table row is actually set in, accounting for the monospace
    /// fallback used when the table could not be fitted to a grid.
    private func tableFont(for line: MDLine) -> NSFont {
        guard let layout = tableLayouts[line.blockID] else { return theme.body }
        guard layout.fits else {
            return FontBuilder.font(
                .mono, size: layout.fontSize,
                weight: line.kind == .tableHeader ? .semibold : .regular)
        }
        return tableFont(line.kind, size: layout.fontSize)
    }

    /// Pins every cell onto the column grid with two kerns: one that puts the
    /// cell's first character exactly one padding past the column edge, and one
    /// that fills the rest of the column.
    private func alignTableRow(_ line: MDLine, text: NSString, storage: NSTextStorage) {
        guard let layout = tableLayouts[line.blockID], layout.fits,
              !layout.columns.isEmpty else { return }

        let font = tableFont(line.kind, size: layout.fontSize)
        let padding = cellPadding(layout.fontSize)
        let pipeWidth = width(of: "|", font: font)
        let pipes = pipePositions(text, in: line.contentRange)
        guard pipes.count >= 2 else { return }

        for column in 0..<(pipes.count - 1) {
            guard column < layout.columns.count else { break }
            let openPipe = pipes[column]
            let cellStart = openPipe + 1
            let cellEnd = pipes[column + 1]

            var contentStart = cellStart
            var contentEnd = cellEnd
            while contentStart < contentEnd, isSpace(text.character(at: contentStart)) {
                contentStart += 1
            }
            while contentEnd > contentStart, isSpace(text.character(at: contentEnd - 1)) {
                contentEnd -= 1
            }

            let leadWidth = span(text, cellStart, contentStart, font)
            let contentWidth = span(text, contentStart, contentEnd, font)
            let trailWidth = span(text, contentEnd, cellEnd, font)
            let segmentTarget = padding * 2 + layout.columns[column]

            // Anchor for the leading run: the last space before the content, or
            // the pipe itself when the cell starts flush against it.
            let leadAnchor = contentStart > cellStart ? contentStart - 1 : openPipe
            // Anchor for the trailing run, falling back inward the same way.
            let tailAnchor = cellEnd > contentEnd
                ? cellEnd - 1
                : (contentEnd > contentStart ? contentEnd - 1 : leadAnchor)

            if tailAnchor == leadAnchor {
                // Nothing in the cell: one kern does the whole column.
                storage.addAttribute(
                    .kern, value: segmentTarget - pipeWidth - leadWidth - trailWidth,
                    range: NSRange(location: leadAnchor, length: 1))
            } else {
                storage.addAttribute(
                    .kern, value: padding - pipeWidth - leadWidth,
                    range: NSRange(location: leadAnchor, length: 1))
                storage.addAttribute(
                    .kern, value: segmentTarget - padding - contentWidth - trailWidth,
                    range: NSRange(location: tailAnchor, length: 1))
            }
        }

        // The closing pipe adds nothing to the grid, so it takes no space.
        if let last = pipes.last, last >= line.contentRange.location {
            storage.addAttribute(
                .kern, value: -pipeWidth, range: NSRange(location: last, length: 1))
        }
    }

    private func span(_ text: NSString, _ from: Int, _ to: Int, _ font: NSFont) -> CGFloat {
        guard to > from else { return 0 }
        return width(of: text.substring(with: NSRange(location: from, length: to - from)), font: font)
    }

    private func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }

    // MARK: - One line

    private func styleLine(
        _ line: MDLine, index: Int, text: NSString, storage: NSTextStorage, context: Context
    ) {
        let colors = theme.colors
        let metrics = theme.metrics

        let contentX = metrics.gutter
            + CGFloat(line.quoteDepth) * metrics.indentStep
            + CGFloat(line.listDepth) * metrics.indentStep

        let markerString = line.markerRange.length > 0
            ? text.substring(with: line.markerRange)
            : ""
        let markerWidth = markerString.isEmpty ? 0 : width(of: markerString, font: theme.marker)

        // With no gap characters to kern, the marker must butt straight up against
        // the content column instead of leaving the standard gap.
        let effectiveGap = line.gapRange.length > 0 ? metrics.gutterGap : 0
        var markerX = contentX - effectiveGap - markerWidth
        if markerX < 0 { markerX = 0 }

        // A line that is only an image becomes the picture itself, with whatever
        // text the line holds falling to the bottom of the block as its caption.
        let image = imageDisplay(for: line)
        let layout: LineLayout
        if let image {
            // The picture lives in the space *before* the paragraph, not inside
            // its line height. Line height applies to every wrapped fragment, so
            // reserving the image there gave a source line that wrapped two
            // picture-tall fragments and a caret the height of the image.
            layout = LineLayout(
                height: metrics.base * 1.5,
                before: metrics.imageTopPadding + image.size.height + metrics.base * 0.45,
                after: metrics.base * 0.9)
        } else {
            layout = lineLayout(for: line)
        }
        let style = paragraphStyle(
            firstIndent: markerString.isEmpty ? contentX : markerX,
            headIndent: contentX,
            lineHeight: layout.height,
            spacingBefore: layout.before,
            spacingAfter: layout.after,
            // A caption belongs under the middle of its picture.
            alignment: image != nil ? .center : .natural
        )

        let base = baseAttributes(for: line, style: style, lineHeight: layout.height)
        storage.setAttributes(base, range: line.fullRange)

        let revealed = markerColor(for: line, context: context)

        // --- Gutter marker -------------------------------------------------
        if line.markerRange.length > 0 {
            var markerInk = revealed ?? NSColor.clear
            if case .thematicBreak = line.kind, revealed != nil {
                markerInk = colors.rule.withAlpha(0.9)
            }
            storage.addAttributes([
                .font: markerFont(for: line.kind),
                .foregroundColor: markerInk,
            ], range: line.markerRange)

            // Kern the final gap character so the content lands exactly on contentX.
            if line.gapRange.length > 0 {
                let gapString = text.substring(with: line.gapRange)
                let natural = width(of: gapString, font: base[.font] as? NSFont ?? theme.body)
                let kern = metrics.gutterGap - natural
                let last = NSRange(location: NSMaxRange(line.gapRange) - 1, length: 1)
                storage.addAttribute(.kern, value: kern, range: last)
            }
        }

        // --- Fenced code gets a light generic highlight ----------------------
        if case .codeLine = line.kind, line.contentRange.length > 0 {
            applyCodeTokens(storage, text: text, range: line.contentRange, language: line.language)
        } else if case .indentedCode = line.kind, line.contentRange.length > 0 {
            applyCodeTokens(storage, text: text, range: line.contentRange, language: nil)
        }

        // --- Inline runs ------------------------------------------------------
        if !line.inlines.isEmpty {
            let sorted = line.inlines.sorted {
                $0.range.location == $1.range.location
                    ? $0.range.length > $1.range.length      // outer wrappers first
                    : $0.range.location < $1.range.location
            }
            for token in sorted {
                apply(token, line: line, revealed: revealed, text: text,
                      storage: storage, context: context)
            }
        }


        // --- Table structure --------------------------------------------------
        // Runs last: the inline pass colours every pipe, so hiding a row has to
        // come after it, and the cell kerning must not be overwritten.
        if line.kind.isTable {
            let isDelimiter = line.kind == .tableDelimiter
            let isEmptyHeader = line.kind == .tableHeader
                && emptyHeaderBlocks.contains(line.blockID)

            if isDelimiter || isEmptyHeader {
                // The drawn rule already says what this row says.
                if revealed == nil, line.range.length > 0 {
                    storage.addAttribute(
                        .foregroundColor, value: NSColor.clear, range: line.range)
                }
            } else {
                alignTableRow(line, text: text, storage: storage)
            }
        }
    }

    // MARK: - Base attributes

    private func baseAttributes(
        for line: MDLine, style: NSParagraphStyle, lineHeight: CGFloat
    ) -> [NSAttributedString.Key: Any] {
        let colors = theme.colors
        var font = theme.body
        var color = colors.text

        switch line.kind {
        case .heading(let level):
            font = theme.heading(level: level)
            color = colors.heading
        case .setextUnderline:
            font = theme.marker
            color = colors.marker
        case .codeLine, .indentedCode:
            font = theme.mono
            color = colors.text
        case .fenceDelimiter:
            font = theme.monoSmall
            color = colors.textSecondary
        case .tableHeader, .tableRow:
            font = tableFont(for: line)
            color = colors.text
        case .tableDelimiter:
            font = theme.monoSmall
            color = colors.marker
        case .frontMatterLine, .frontMatterDelimiter:
            font = theme.monoSmall
            color = colors.textSecondary
        case .htmlLine:
            font = theme.monoSmall
            color = colors.textSecondary
        case .footnoteDefinition:
            font = FontBuilder.font(theme.preset.bodyFamily, size: theme.metrics.base * 0.94)
            color = colors.textSecondary
        case .linkDefinition:
            font = theme.monoSmall
            color = colors.textSecondary
        case .blockquote, .calloutTitle:
            color = colors.quoteText
        case .thematicBreak:
            font = theme.marker
            color = colors.rule
        case .definition:
            color = colors.textSecondary
        default:
            break
        }

        if line.blockImage != nil, imageDisplay(for: line) != nil {
            // Everything on this line is caption: the syntax around the alt text
            // collapses away, leaving the description sitting under the picture.
            font = FontBuilder.font(theme.preset.bodyFamily, size: theme.metrics.base * 0.86)
            color = colors.textSecondary
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]

        // Forcing a line height taller than the font's natural one makes TextKit
        // put all the extra space above the glyphs, so the text sits on the
        // bottom of its line. Lifting the baseline by half the surplus centres it
        // again, which is what makes checkboxes, highlights and inline code
        // backgrounds line up with the words next to them.
        let surplus = lineHeight - naturalLineHeight(of: font)
        if surplus > 0.5 {
            attributes[.baselineOffset] = surplus / 2
        }

        if theme.preset.bodyTracking != 0, !line.kind.isCode, !line.kind.isTable {
            attributes[.kern] = theme.preset.bodyTracking * theme.metrics.base
        }
        return attributes
    }

    /// The height TextKit would give a line set in this font, cached because it
    /// is asked for on every line of every restyle.
    private func naturalLineHeight(of font: NSFont) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)"
        if let cached = lineHeights[key] { return cached }
        let value = ceil(font.ascender + abs(font.descender) + font.leading)
        lineHeights[key] = value
        return value
    }

    private func markerFont(for kind: BlockKind) -> NSFont {
        switch kind {
        case .heading(let level) where level <= 2:
            return theme.markerBold
        default:
            return theme.marker
        }
    }

    /// Ink for this line's syntax markers, or nil when they should be invisible.
    ///
    /// Markers show only inside the element the selection is in. Everywhere else
    /// the document reads as finished prose, which is the whole point of the
    /// hanging gutter: structure without clutter.
    private func markerColor(for line: MDLine, context: Context) -> NSColor? {
        if context.activeBlockIDs.contains(line.blockID) { return theme.colors.markerActive }
        if context.alwaysShowMarkers { return theme.colors.marker }

        // List markers are not decoration, they are what makes a list read as a
        // list, so they stay. Unordered bullets are hidden here only because the
        // text view draws a proper dot in their place.
        if case .listItem(let ordered, _) = line.kind {
            return ordered ? theme.colors.marker : nil
        }
        // A definition's label is its whole point; hiding it would leave a bare
        // URL with nothing to say what it defines.
        if line.kind == .linkDefinition || line.kind == .footnoteDefinition {
            return theme.colors.marker
        }
        return nil
    }

    /// Resolved image for a line that is nothing but an image, with the size it
    /// should be drawn at.
    func imageDisplay(for line: MDLine) -> (url: URL, size: NSSize)? {
        guard let block = line.blockImage,
              let url = ImageStore.shared.resolve(block.destination, relativeTo: baseURL),
              let image = ImageStore.shared.image(at: url) else { return nil }
        let size = ImageStore.shared.displaySize(
            for: image,
            measure: theme.metrics.measure,
            maximumHeight: theme.metrics.base * 26)
        return (url, size)
    }



    /// True when this line's bullet should be drawn as a dot rather than shown
    /// as its literal `-`, `*` or `+`.
    static func drawsBulletDot(_ line: MDLine, context: Context) -> Bool {
        guard case .listItem(let ordered, _) = line.kind, !ordered else { return false }
        if context.alwaysShowMarkers { return false }
        return !context.activeBlockIDs.contains(line.blockID)
    }

    // MARK: - Inline runs

    private func apply(
        _ token: InlineToken, line: MDLine, revealed: NSColor?, text: NSString,
        storage: NSTextStorage, context: Context
    ) {
        let colors = theme.colors
        let range = token.range
        guard range.length > 0, NSMaxRange(range) <= storage.length else { return }

        switch token.kind {
        case .syntax:
            if let revealed {
                storage.addAttribute(.foregroundColor, value: revealed, range: range)
            } else {
                // Hide the delimiters and collapse them to zero width, rather
                // than leaving a hole in the line where they used to be.
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                collapse(range, in: storage, text: text)
            }

        case .strong:
            addTraits(storage, range: range, bold: true, italic: false)

        case .emphasis:
            addTraits(storage, range: range, bold: false, italic: true)

        case .strongEmphasis:
            addTraits(storage, range: range, bold: true, italic: true)

        case .strikethrough:
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: colors.textSecondary,
                .foregroundColor: colors.textSecondary,
            ], range: range)

        case .highlight:
            storage.addAttribute(.backgroundColor, value: colors.highlightBackground, range: range)

        case .code:
            storage.addAttributes([
                .font: theme.mono,
                .foregroundColor: colors.code,
                .backgroundColor: colors.codeBackground,
            ], range: range)

        case .linkText:
            storage.addAttributes([
                .foregroundColor: colors.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: colors.link.withAlpha(0.35),
            ], range: range)

        case .autolink:
            storage.addAttributes([
                .foregroundColor: colors.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: colors.link.withAlpha(0.35),
            ], range: range)

        case .linkURL:
            // The destination is plumbing. It shows only while the caret is in
            // the link, which is when you would want to edit it.
            if let revealed {
                storage.addAttributes([
                    .font: theme.monoSmall,
                    .foregroundColor: revealed,
                ], range: range)
            } else {
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                collapse(range, in: storage, text: text)
            }

        case .imageAlt:
            storage.addAttributes([
                .foregroundColor: colors.textSecondary,
            ], range: range)
            addTraits(storage, range: range, bold: false, italic: true)

        case .footnoteRef:
            storage.addAttributes([
                .font: FontBuilder.font(theme.preset.bodyFamily, size: theme.metrics.base * 0.78),
                .foregroundColor: colors.accent,
                .baselineOffset: theme.metrics.base * 0.28,
            ], range: range)

        case .math:
            storage.addAttributes([
                .font: theme.mono,
                .foregroundColor: colors.accent,
            ], range: range)

        case .html:
            storage.addAttributes([
                .font: theme.monoSmall,
                .foregroundColor: colors.textSecondary.withAlpha(0.8),
            ], range: range)

        case .escape:
            break  // the escaped character keeps the line's base styling

        case .taskMarker(let state):
            // The `[ ]` text is never shown. It is squeezed down to exactly the
            // width of a checkbox, which the text view then draws in its place.
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
            collapse(range, in: storage, text: text, to: theme.metrics.checkboxAdvance)
            if state == .done {
                let rest = NSRange(
                    location: NSMaxRange(range),
                    length: max(0, NSMaxRange(line.contentRange) - NSMaxRange(range)))
                if rest.length > 0 {
                    storage.addAttributes([
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: colors.taskDone,
                        .foregroundColor: colors.taskDone,
                    ], range: rest)
                }
            }

        case .calloutLabel(let kind):
            let palette = theme.callout(kind)
            if revealed != nil {
                // Caret is in the callout, so show the raw `[!NOTE]` to edit.
                storage.addAttributes([
                    .font: theme.calloutTitle,
                    .foregroundColor: palette.accent,
                ], range: range)
            } else {
                // Otherwise squeeze the raw label down to the width of its
                // proper title, which the text view draws in its place.
                let title = kind?.title ?? "Note"
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                collapse(range, in: storage, text: text,
                         to: width(of: title, font: theme.calloutTitle))
            }

        case .tablePipe:
            // Pipes are scaffolding. Once the cells are on a grid they say
            // nothing the columns do not, so they only show while editing, or
            // when the table was too wide to fit and there is no grid.
            let visible = revealed ?? (tableFits(blockID: line.blockID) ? nil : colors.marker)
            storage.addAttribute(.foregroundColor, value: visible ?? NSColor.clear, range: range)

        case .hardBreak:
            storage.addAttribute(.backgroundColor, value: colors.marker.withAlpha(0.18), range: range)
        }
    }

    /// Kerns a run down to `target` points wide (zero by default) without
    /// touching the characters themselves, so the document on disk is unchanged.
    private func collapse(
        _ range: NSRange, in storage: NSTextStorage, text: NSString, to target: CGFloat = 0
    ) {
        guard range.length > 0 else { return }
        var font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? theme.body

        if target == 0 {
            // Kerning alone cannot pull a run all the way to nothing: a negative
            // kern is clamped at each glyph's own advance, so narrow characters
            // absorb less than their share and a hidden URL still leaves a gap.
            // Shrinking the glyphs first leaves only a rounding error to kern away.
            font = NSFont(descriptor: font.fontDescriptor, size: 0.5) ?? font
            storage.addAttribute(.font, value: font, range: range)
        }

        let natural = width(of: text.substring(with: range), font: font)
        let adjustment = (target - natural) / CGFloat(range.length)
        storage.addAttribute(.kern, value: adjustment, range: range)
    }

    private func applyCodeTokens(
        _ storage: NSTextStorage, text: NSString, range: NSRange, language: String?
    ) {
        let colors = theme.colors
        for token in CodeHighlighter.tokens(text, range: range, language: language) {
            guard NSMaxRange(token.range) <= storage.length else { continue }
            let color: NSColor
            switch token.kind {
            case .comment: color = colors.textSecondary.withAlpha(0.75)
            case .string: color = colors.code
            case .number: color = colors.accent
            case .keyword: color = colors.link
            }
            storage.addAttribute(.foregroundColor, value: color, range: token.range)
        }
    }

    // MARK: - Focus mode

    /// Fades every line outside the caret's paragraph. Run after `style`, over
    /// the same line range, so it sees final colours.
    func applyFocusDimming(
        _ storage: NSTextStorage,
        document: ParsedDocument,
        lines lineRange: Range<Int>,
        activeParagraphID: Int?
    ) {
        let clamped = lineRange.clamped(to: 0..<document.lines.count)
        guard !clamped.isEmpty else { return }

        storage.beginEditing()
        for index in clamped {
            let line = document.lines[index]
            guard line.paragraphID != activeParagraphID, line.fullRange.length > 0 else { continue }
            storage.enumerateAttribute(.foregroundColor, in: line.fullRange) { value, range, _ in
                guard let color = value as? NSColor else { return }
                storage.addAttribute(
                    .foregroundColor,
                    value: color.withAlpha(color.alphaComponent * 0.3),
                    range: range)
            }
        }
        storage.endEditing()
    }

    // MARK: - Helpers

    private struct LineLayout {
        let height: CGFloat
        let before: CGFloat
        let after: CGFloat
    }

    private func lineLayout(for line: MDLine) -> LineLayout {
        let base = theme.metrics.base

        // A delimiter row, and a header row with nothing in it, are structure
        // rather than content. Both are given a fixed compact height so that
        // revealing their text when the caret arrives does not shift the page.
        if line.kind == .tableDelimiter
            || (line.kind == .tableHeader && emptyHeaderBlocks.contains(line.blockID)) {
            return LineLayout(height: base * 1.15, before: 0, after: 0)
        }

        switch line.kind {
        case .heading(let level):
            let size = theme.headingSize(level: level)
            return LineLayout(
                height: size * 1.28,
                before: base * (level == 1 ? 1.15 : level == 2 ? 0.95 : 0.75),
                after: base * 0.22)
        case .codeLine, .indentedCode:
            return LineLayout(height: base * 1.48, before: 0, after: 0)
        case .fenceDelimiter, .frontMatterDelimiter:
            // The delimiter is usually invisible, so it reads as the block's top
            // and bottom padding. Kept at a fixed height so revealing it on the
            // caret does not shift the page.
            return LineLayout(height: base * 0.95, before: 0, after: 0)
        case .setextUnderline:
            return LineLayout(height: base * 0.6, before: 0, after: 0)
        case .tableHeader, .tableRow:
            return LineLayout(height: tableFontSize(for: line) * 1.85, before: 0, after: 0)
        case .tableDelimiter:
            return LineLayout(height: base * 1.15, before: 0, after: 0)
        case .frontMatterLine:
            return LineLayout(height: base * 1.45, before: 0, after: 0)
        case .listItem, .definition:
            return LineLayout(height: theme.metrics.lineHeight, before: 0, after: base * 0.1)
        case .thematicBreak:
            return LineLayout(height: base * 1.6, before: base * 0.5, after: base * 0.5)
        case .blank:
            return LineLayout(height: theme.metrics.lineHeight * 0.7, before: 0, after: 0)
        default:
            return LineLayout(height: theme.metrics.lineHeight, before: 0, after: 0)
        }
    }

    private func paragraphStyle(
        firstIndent: CGFloat, headIndent: CGFloat, lineHeight: CGFloat,
        spacingBefore: CGFloat, spacingAfter: CGFloat,
        alignment: NSTextAlignment = .natural
    ) -> NSParagraphStyle {
        let key = "\(round(firstIndent))|\(round(headIndent))|\(round(lineHeight))|\(round(spacingBefore))|\(round(spacingAfter))|\(alignment.rawValue)"
        if let cached = paragraphStyles[key] { return cached }

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = max(0, firstIndent)
        style.headIndent = max(0, headIndent)
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        // Keeps CJK and long URLs from overflowing the measure.
        style.lineBreakStrategy = .standard

        paragraphStyles[key] = style
        return style
    }

    private func width(of string: String, font: NSFont) -> CGFloat {
        let key = "\(string)|\(font.fontName)|\(font.pointSize)"
        if let cached = markerWidths[key] { return cached }
        let value = (string as NSString).size(withAttributes: [.font: font]).width
        markerWidths[key] = value
        return value
    }

    private func addTraits(_ storage: NSTextStorage, range: NSRange, bold: Bool, italic: Bool) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let converted = self.font(font, bold: bold, italic: italic)
            storage.addAttribute(.font, value: converted, range: subrange)
        }
    }

    private func font(_ font: NSFont, bold: Bool, italic: Bool) -> NSFont {
        let key = "\(font.fontName)|\(font.pointSize)|\(bold)|\(italic)"
        if let cached = traitFonts[key] { return cached }

        var result = font
        let manager = NSFontManager.shared
        if bold { result = manager.convert(result, toHaveTrait: .boldFontMask) }
        if italic { result = manager.convert(result, toHaveTrait: .italicFontMask) }
        traitFonts[key] = result
        return result
    }
}

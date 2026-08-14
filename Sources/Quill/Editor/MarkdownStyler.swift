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

    // MARK: - One line

    private func styleLine(
        _ line: MDLine, index: Int, text: NSString, storage: NSTextStorage, context: Context
    ) {
        // A parse can outlive the text it describes by a moment. Writing
        // attributes outside the storage raises, and AppKit turns a raise during
        // drawing into a crash.
        guard NSMaxRange(line.fullRange) <= storage.length else { return }

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
            alignment: image != nil ? .center : .natural,
            // The container is as wide as the widest table in the document, so
            // prose is held to the measure here instead of by the container.
            // A table gets no tail indent and runs on to its natural width.
            tailIndent: line.kind.isTable ? 0 : metrics.contentWidth
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

        // --- Table pipes fade back so the cells read as columns ---------------
        if line.kind.isTable {
            dimPipes(in: line, text: text, storage: storage)
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


    }

    /// How wide a table of this many characters wants to be.
    ///
    /// Monospace makes this arithmetic rather than a layout pass: one advance
    /// times the longest row. The text container is widened to the answer so a
    /// table that will not fit the measure can be scrolled to instead of being
    /// shrunk or, worse, wrapped.
    func tableWidth(characters: Int) -> CGFloat {
        guard characters > 0 else { return 0 }
        // The panel behind a table is drawn 14pt wider than the text on each
        // side, so the container has to leave room for it or the rounded corner
        // falls off the end of the view.
        return theme.metrics.gutter + CGFloat(characters) * monoAdvance(theme.monoSmall) + 34
    }

    /// Width of one character in a monospace face. Uniform by definition, so it
    /// is measured once per font and kept.
    private func monoAdvance(_ font: NSFont) -> CGFloat {
        width(of: "0", font: font)
    }

    /// Tints the `|` separators, leaving the cells at full strength. A single
    /// character walk, no measuring: the column positions come from the padding
    /// `TableFormatter` writes into the file, not from anything worked out here.
    private func dimPipes(in line: MDLine, text: NSString, storage: NSTextStorage) {
        let start = line.range.location
        let end = NSMaxRange(line.range)
        guard end <= storage.length else { return }

        let ink = theme.colors.marker.withAlpha(0.7)
        var index = start
        while index < end {
            if text.character(at: index) == 124 {
                storage.addAttribute(.foregroundColor, value: ink,
                                     range: NSRange(location: index, length: 1))
            }
            index += 1
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
        case .tableRow(let header):
            font = header ? theme.monoSmallBold : theme.monoSmall
            color = colors.text
        case .tableDelimiter:
            font = theme.monoSmall
            color = colors.textSecondary.withAlpha(0.55)
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

        // Letter spacing would widen every cell by a different amount and pull
        // the columns apart, so a table is set at the font's own spacing.
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

        switch line.kind {
        case .heading(let level):
            let size = theme.headingSize(level: level)
            return LineLayout(
                height: size * 1.28,
                before: base * (level == 1 ? 1.15 : level == 2 ? 0.95 : 0.75),
                after: base * 0.22)
        case .codeLine, .indentedCode:
            return LineLayout(height: base * 1.48, before: 0, after: 0)
        case .tableRow, .tableDelimiter:
            // The panel needs air around it, but only at the block's edges: put
            // it on every line and the rows would drift apart inside the table.
            return LineLayout(
                height: base * 1.55,
                before: line.isBlockStart ? base * 1.1 : 0,
                after: line.isBlockEnd ? base * 1.1 : 0)
        case .fenceDelimiter, .frontMatterDelimiter:
            // The delimiter is usually invisible, so it reads as the block's top
            // and bottom padding. Kept at a fixed height so revealing it on the
            // caret does not shift the page.
            return LineLayout(height: base * 0.95, before: 0, after: 0)
        case .setextUnderline:
            return LineLayout(height: base * 0.6, before: 0, after: 0)
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
        alignment: NSTextAlignment = .natural,
        tailIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let key = "\(round(firstIndent))|\(round(headIndent))|\(round(lineHeight))|\(round(spacingBefore))|\(round(spacingAfter))|\(alignment.rawValue)|\(round(tailIndent))"
        if let cached = paragraphStyles[key] { return cached }

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = max(0, firstIndent)
        style.headIndent = max(0, headIndent)
        style.tailIndent = tailIndent
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

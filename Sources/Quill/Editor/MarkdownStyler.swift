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

    private var markerWidths: [String: CGFloat] = [:]
    private var paragraphStyles: [String: NSParagraphStyle] = [:]
    private var traitFonts: [String: NSFont] = [:]

    init(theme: Theme) {
        self.theme = theme
    }

    func update(theme: Theme) {
        guard theme.identifier != self.theme.identifier else { return }
        self.theme = theme
        markerWidths.removeAll()
        paragraphStyles.removeAll()
        traitFonts.removeAll()
    }

    struct Context {
        /// Blocks the selection touches. Markers are revealed only inside these,
        /// so a heading reads as a heading until you put the caret in it.
        var activeBlockIDs: Set<Int> = []
        /// Block the caret sits in, used by focus mode.
        var activeBlockID: Int?
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

        let layout = lineLayout(for: line.kind)
        let style = paragraphStyle(
            firstIndent: markerString.isEmpty ? contentX : markerX,
            headIndent: contentX,
            lineHeight: layout.height,
            spacingBefore: layout.before,
            spacingAfter: layout.after
        )

        let base = baseAttributes(for: line, style: style)
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
        guard !line.inlines.isEmpty else { return }
        let sorted = line.inlines.sorted {
            $0.range.location == $1.range.location
                ? $0.range.length > $1.range.length          // outer wrappers first
                : $0.range.location < $1.range.location
        }
        for token in sorted {
            apply(token, line: line, revealed: revealed, text: text, storage: storage, context: context)
        }
    }

    // MARK: - Base attributes

    private func baseAttributes(
        for line: MDLine, style: NSParagraphStyle
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
        case .tableHeader:
            font = FontBuilder.font(.mono, size: theme.metrics.base * 0.92, weight: .semibold)
            color = colors.text
        case .tableRow, .tableDelimiter:
            font = theme.mono
            color = colors.text
        case .frontMatterLine, .frontMatterDelimiter:
            font = theme.monoSmall
            color = colors.textSecondary
        case .htmlLine:
            font = theme.monoSmall
            color = colors.textSecondary
        case .footnoteDefinition:
            font = FontBuilder.font(theme.preset.bodyFamily, size: theme.metrics.base * 0.94)
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

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        if theme.preset.bodyTracking != 0, !line.kind.isCode {
            attributes[.kern] = theme.preset.bodyTracking * theme.metrics.base
        }
        return attributes
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
        return nil
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
            storage.addAttributes([
                .font: theme.monoSmall,
                .foregroundColor: colors.textSecondary.withAlpha(0.75),
            ], range: range)

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
            storage.addAttribute(.foregroundColor, value: colors.marker, range: range)

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
        let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            ?? theme.body
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

    /// Fades every line outside the caret's block. Run after `style`, over the
    /// same line range, so it sees final colours.
    func applyFocusDimming(
        _ storage: NSTextStorage,
        document: ParsedDocument,
        lines lineRange: Range<Int>,
        activeBlockID: Int?
    ) {
        let clamped = lineRange.clamped(to: 0..<document.lines.count)
        guard !clamped.isEmpty else { return }

        storage.beginEditing()
        for index in clamped {
            let line = document.lines[index]
            guard line.blockID != activeBlockID, line.fullRange.length > 0 else { continue }
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

    private func lineLayout(for kind: BlockKind) -> LineLayout {
        let base = theme.metrics.base
        switch kind {
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
        case .tableHeader, .tableRow, .tableDelimiter:
            return LineLayout(height: base * 1.55, before: 0, after: 0)
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
        spacingBefore: CGFloat, spacingAfter: CGFloat
    ) -> NSParagraphStyle {
        let key = "\(round(firstIndent))|\(round(headIndent))|\(round(lineHeight))|\(round(spacingBefore))|\(round(spacingAfter))"
        if let cached = paragraphStyles[key] { return cached }

        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = max(0, firstIndent)
        style.headIndent = max(0, headIndent)
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
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

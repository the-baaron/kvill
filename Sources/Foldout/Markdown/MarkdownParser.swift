import Foundation

/// A line-oriented Markdown scanner.
///
/// It is deliberately not a full CommonMark implementation: Foldout never converts
/// the document to HTML, it only needs to know what each line *is* so it can be
/// styled and indented. That makes a single left-to-right pass enough, and keeps
/// re-parsing cheap enough to run on every keystroke.
enum MarkdownParser {

    static func parse(_ string: NSString) -> ParsedDocument {
        parse(scan: Scan(string))
    }

    static func parse(scan text: Scan) -> ParsedDocument {
        var lines = splitLines(text)
        guard !lines.isEmpty else { return ParsedDocument(lines: []) }

        classify(&lines, text: text)
        // Before the setext pass, so a header row is no longer a paragraph by the
        // time an underline below it is looked at.
        detectTables(&lines, text: text)
        detectSetextHeadings(&lines, text: text)
        assignBlocks(&lines)
        scanInlines(&lines, text: text)
        detectBlockImages(&lines, text: text)

        return ParsedDocument(lines: lines, linkDefinitions: collectDefinitions(lines, text: text))
    }

    // MARK: - Line splitting

    private static func splitLines(_ text: Scan) -> [MDLine] {
        var result: [MDLine] = []
        let length = text.length
        result.reserveCapacity(length / 40 + 8)

        var start = 0
        var index = 0
        var number = 0
        while index < length {
            let character = text.chr(index)
            guard isNewline(character) else {
                index += 1
                continue
            }
            // CRLF is one line break, not two.
            var end = index + 1
            if character == 13, end < length, text.chr(end) == 10 { end += 1 }
            result.append(MDLine(
                number: number,
                range: NSRange(location: start, length: index - start),
                fullRange: NSRange(location: start, length: end - start)))
            number += 1
            start = end
            index = end
        }

        // Whatever follows the last break, including the empty line a trailing
        // one leaves behind.
        result.append(MDLine(
            number: number,
            range: NSRange(location: start, length: length - start),
            fullRange: NSRange(location: start, length: length - start)))
        return result
    }

    // MARK: - Structural classification

    private static func classify(_ lines: inout [MDLine], text: Scan) {
        var fenceOpen = false
        var fenceChar: unichar = 0
        var fenceLength = 0
        var fenceLanguage: String?
        var frontMatterOpen = false
        var frontMatterClosed = false
        var previousWasBlank = true
        var previousWasIndentedCode = false

        for index in lines.indices {
            var line = lines[index]
            let start = line.range.location
            let end = NSMaxRange(line.range)

            // --- YAML front matter, only valid as the very first line ---------
            if index == 0, !frontMatterClosed, isFence(text, start, end, char: 45, minimum: 3) {
                frontMatterOpen = true
                line.kind = .frontMatterDelimiter
                line.markerRange = NSRange(location: start, length: end - start)
                line.contentRange = NSRange(location: end, length: 0)
                lines[index] = line
                continue
            }
            if frontMatterOpen {
                if isFence(text, start, end, char: 45, minimum: 3)
                    || isFence(text, start, end, char: 46, minimum: 3) {
                    frontMatterOpen = false
                    frontMatterClosed = true
                    line.kind = .frontMatterDelimiter
                    line.markerRange = NSRange(location: start, length: end - start)
                } else {
                    line.kind = .frontMatterLine
                    line.contentRange = line.range
                }
                lines[index] = line
                continue
            }

            // --- Inside a fenced code block -----------------------------------
            if fenceOpen {
                var cursor = start
                var indent = 0
                while cursor < end, isSpace(text.chr(cursor)), indent < 3 {
                    cursor += 1
                    indent += 1
                }
                if isFence(text, cursor, end, char: fenceChar, minimum: fenceLength) {
                    fenceOpen = false
                    line.kind = .fenceDelimiter(language: nil)
                    line.markerRange = NSRange(location: cursor, length: end - cursor)
                } else {
                    line.kind = .codeLine
                    line.contentRange = line.range
                    line.language = fenceLanguage
                }
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Blank ---------------------------------------------------------
            if isBlank(text, start, end) {
                line.kind = .blank
                line.contentRange = line.range
                lines[index] = line
                previousWasBlank = true
                previousWasIndentedCode = false
                continue
            }

            // --- Leading indent -------------------------------------------------
            var cursor = start
            var indentColumns = 0
            while cursor < end {
                let c = text.chr(cursor)
                if c == 32 { indentColumns += 1 } else if c == 9 { indentColumns += 4 } else { break }
                cursor += 1
            }
            let firstNonSpace = cursor

            // --- Blockquote markers ----------------------------------------------
            var quoteDepth = 0
            var markerEnd = firstNonSpace
            while cursor < end, text.chr(cursor) == 62 {  // '>'
                quoteDepth += 1
                cursor += 1
                markerEnd = cursor
                while cursor < end, isSpace(text.chr(cursor)) { cursor += 1 }
            }
            line.quoteDepth = quoteDepth

            let innerStart = cursor
            let innerIndent = quoteDepth > 0 ? 0 : indentColumns

            // --- Indented code block ----------------------------------------------
            if quoteDepth == 0, indentColumns >= 4, previousWasBlank || previousWasIndentedCode {
                line.kind = .indentedCode
                line.contentRange = line.range
                lines[index] = line
                previousWasBlank = false
                previousWasIndentedCode = true
                continue
            }
            previousWasIndentedCode = false

            // --- Fence opener --------------------------------------------------------
            if let fence = fenceOpener(text, innerStart, end) {
                fenceOpen = true
                fenceChar = fence.char
                fenceLength = fence.length
                fenceLanguage = fence.language
                line.kind = .fenceDelimiter(language: fence.language)
                line.language = fence.language
                line.markerRange = NSRange(location: firstNonSpace, length: fence.markerEnd - firstNonSpace)
                let gapEnd = skipSpaces(text, fence.markerEnd, end)
                line.gapRange = NSRange(location: fence.markerEnd, length: gapEnd - fence.markerEnd)
                line.contentRange = NSRange(location: gapEnd, length: end - gapEnd)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Setext underline (resolved later, needs the previous line) ---------
            if quoteDepth == 0, let level = setextLevel(text, innerStart, end) {
                line.kind = .setextUnderline(level: level)
                line.markerRange = NSRange(location: firstNonSpace, length: end - firstNonSpace)
                line.contentRange = NSRange(location: end, length: 0)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Thematic break -------------------------------------------------------
            if isThematicBreak(text, innerStart, end) {
                line.kind = .thematicBreak
                line.markerRange = NSRange(location: firstNonSpace, length: end - firstNonSpace)
                line.contentRange = NSRange(location: end, length: 0)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- ATX heading -------------------------------------------------------------
            if let heading = atxHeading(text, innerStart, end) {
                line.kind = .heading(level: heading.level)
                line.markerRange = NSRange(location: firstNonSpace, length: heading.markerEnd - firstNonSpace)
                line.gapRange = NSRange(location: heading.markerEnd, length: heading.contentStart - heading.markerEnd)
                line.contentRange = NSRange(location: heading.contentStart, length: end - heading.contentStart)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- List item -------------------------------------------------------------------
            if let item = listMarker(text, innerStart, end) {
                // The checkbox stays inline so it can be clicked; only the bullet hangs.
                let task = taskCheckbox(text, item.contentStart, end)?.state
                line.kind = .listItem(ordered: item.ordered, task: task)
                line.listDepth = innerIndent / 2
                line.markerRange = NSRange(location: firstNonSpace, length: item.markerEnd - firstNonSpace)
                line.gapRange = NSRange(location: item.markerEnd, length: item.contentStart - item.markerEnd)
                line.contentRange = NSRange(location: item.contentStart, length: end - item.contentStart)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Callout title, e.g. `> [!NOTE]` ------------------------------------------------
            if quoteDepth > 0, let callout = calloutLabel(text, innerStart, end) {
                line.kind = .calloutTitle(kind: callout.kind)
                line.markerRange = NSRange(location: firstNonSpace, length: markerEnd - firstNonSpace)
                line.gapRange = NSRange(location: markerEnd, length: innerStart - markerEnd)
                line.contentRange = NSRange(location: innerStart, length: end - innerStart)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Footnote definition -------------------------------------------------------------
            if let footnote = footnoteDefinition(text, innerStart, end) {
                line.kind = .footnoteDefinition
                line.markerRange = NSRange(location: firstNonSpace, length: footnote.markerEnd - firstNonSpace)
                let gapEnd = skipSpaces(text, footnote.markerEnd, end)
                line.gapRange = NSRange(location: footnote.markerEnd, length: gapEnd - footnote.markerEnd)
                line.contentRange = NSRange(location: gapEnd, length: end - gapEnd)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Link reference definition, `[label]: destination` ------------------------------------
            if let definition = linkDefinition(text, innerStart, end) {
                line.kind = .linkDefinition
                line.markerRange = NSRange(location: firstNonSpace, length: definition.markerEnd - firstNonSpace)
                let gapEnd = skipSpaces(text, definition.markerEnd, end)
                line.gapRange = NSRange(location: definition.markerEnd, length: gapEnd - definition.markerEnd)
                line.contentRange = NSRange(location: gapEnd, length: end - gapEnd)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Definition list item ---------------------------------------------------------------
            if quoteDepth == 0, innerStart < end, text.chr(innerStart) == 58,  // ':'
                innerStart + 1 < end, isSpace(text.chr(innerStart + 1)) {
                line.kind = .definition
                line.markerRange = NSRange(location: innerStart, length: 1)
                let gapEnd = skipSpaces(text, innerStart + 1, end)
                line.gapRange = NSRange(location: innerStart + 1, length: gapEnd - innerStart - 1)
                line.contentRange = NSRange(location: gapEnd, length: end - gapEnd)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Raw HTML -----------------------------------------------------------------------------
            if innerStart < end, text.chr(innerStart) == 60, isHTMLBlockStart(text, innerStart, end) {
                line.kind = .htmlLine
                line.contentRange = NSRange(location: innerStart, length: end - innerStart)
                lines[index] = line
                previousWasBlank = false
                continue
            }

            // --- Plain text, possibly inside a quote ---------------------------------------------------
            line.kind = quoteDepth > 0 ? .blockquote : .paragraph
            if quoteDepth > 0 {
                line.markerRange = NSRange(location: firstNonSpace, length: markerEnd - firstNonSpace)
                line.gapRange = NSRange(location: markerEnd, length: innerStart - markerEnd)
            } else {
                line.listDepth = innerIndent >= 2 ? innerIndent / 2 : 0
            }
            line.contentRange = NSRange(location: innerStart, length: end - innerStart)
            lines[index] = line
            previousWasBlank = false
        }
    }

    // MARK: - Tables

    /// Marks the lines of a GitHub-style table.
    ///
    /// A table is a row of pipe-separated cells, a delimiter row of dashes
    /// directly under it, and however many rows follow before a blank line or a
    /// line that is not a row. Nothing is measured here: the table is shown as
    /// aligned monospace source, and `TableFormatter` is what keeps the columns
    /// lined up in the file.
    private static func detectTables(_ lines: inout [MDLine], text: Scan) {
        var index = 0
        while index + 1 < lines.count {
            guard isRowCandidate(lines[index], text: text),
                  isDelimiterRow(lines[index + 1], text: text) else {
                index += 1
                continue
            }

            mark(&lines[index], as: .tableRow(header: true))
            mark(&lines[index + 1], as: .tableDelimiter)

            var row = index + 2
            while row < lines.count, isRowCandidate(lines[row], text: text) {
                mark(&lines[row], as: .tableRow(header: false))
                row += 1
            }

            // The longest row is the table's width, in characters. Every line
            // carries it so the styler can size the block from any one of them.
            var widest = 0
            for line in index..<row { widest = max(widest, lines[line].range.length) }
            for line in index..<row { lines[line].tableWidth = widest }

            index = row
        }
    }

    private static func mark(_ line: inout MDLine, as kind: BlockKind) {
        line.kind = kind
        // A table is flush with the text column: no gutter marker, no indent
        // carried over from however the line was written.
        line.markerRange = NSRange(location: line.range.location, length: 0)
        line.gapRange = NSRange(location: line.range.location, length: 0)
        line.listDepth = 0
    }

    /// A plain paragraph line, outside any quote, holding at least one unescaped
    /// pipe.
    private static func isRowCandidate(_ line: MDLine, text: Scan) -> Bool {
        guard line.kind == .paragraph, line.quoteDepth == 0 else { return false }
        let start = line.range.location
        let end = NSMaxRange(line.range)
        var index = start
        while index < end {
            if text.chr(index) == 124, !isEscaped(text, index, from: start) { return true }
            index += 1
        }
        return false
    }

    /// `| --- | :-: |`: pipes, dashes, colons and spaces, with at least one pipe,
    /// and every cell a run of dashes with optional colons around it.
    private static func isDelimiterRow(_ line: MDLine, text: Scan) -> Bool {
        let start = line.range.location
        let end = NSMaxRange(line.range)
        guard end > start else { return false }

        var sawPipe = false
        var sawDash = false
        var cellDashes = 0
        var cellValid = true
        var sawCell = false

        var index = start
        while index < end {
            let character = text.chr(index)
            switch character {
            case 124:                       // |
                if sawCell, cellDashes == 0 { cellValid = false }
                if sawCell, !cellValid { return false }
                sawPipe = true
                cellDashes = 0
                cellValid = true
                sawCell = false
            case 45:                        // -
                cellDashes += 1
                sawDash = true
                sawCell = true
            case 58:                        // :
                sawCell = true
            case 32, 9:
                break
            default:
                return false
            }
            index += 1
        }
        if sawCell, cellDashes == 0 { return false }
        return sawPipe && sawDash
    }

    // MARK: - Setext headings

    /// Turns the paragraph lines directly above a `===` / `---` underline into a heading.
    private static func detectSetextHeadings(_ lines: inout [MDLine], text: Scan) {
        for index in lines.indices {
            guard case .setextUnderline(let level) = lines[index].kind else { continue }
            var above = index - 1
            var converted = false
            while above >= 0, lines[above].kind == .paragraph {
                lines[above].kind = .heading(level: level)
                converted = true
                above -= 1
            }
            if !converted {
                // Nothing above it: a lone `---` is a thematic break after all.
                lines[index].kind = .thematicBreak
            }
        }
    }

    // MARK: - Block grouping

    private static func assignBlocks(_ lines: inout [MDLine]) {
        var blockID = 0
        var previousSignature: String?
        var paragraphID = 0
        var previousWasBlank = true

        for index in lines.indices {
            let signature = groupSignature(lines[index])
            if signature == nil || signature != previousSignature {
                blockID += 1
            }
            previousSignature = signature
            lines[index].blockID = blockID

            // A run of non-blank lines is one paragraph, however many block
            // kinds it contains.
            let isBlank = lines[index].kind == .blank
            if !isBlank, previousWasBlank { paragraphID += 1 }
            previousWasBlank = isBlank
            lines[index].paragraphID = paragraphID

            lines[index].decoration = decoration(for: lines[index])
        }

        for index in lines.indices {
            lines[index].isBlockStart = index == 0 || lines[index - 1].blockID != lines[index].blockID
            lines[index].isBlockEnd =
                index == lines.count - 1 || lines[index + 1].blockID != lines[index].blockID
        }

        // A quote block that opens with `> [!NOTE]` is a callout all the way down,
        // not just on its title line.
        var index = 0
        while index < lines.count {
            guard lines[index].quoteDepth > 0 else { index += 1; continue }
            let blockStart = index
            let id = lines[index].blockID
            var end = index
            while end < lines.count, lines[end].blockID == id, lines[end].quoteDepth > 0 { end += 1 }
            if case .calloutTitle(let kind) = lines[blockStart].kind {
                for i in blockStart..<end { lines[i].decoration = .callout(kind: kind) }
            }
            index = end
        }
    }

    private static func groupSignature(_ line: MDLine) -> String? {
        switch line.kind {
        case .codeLine, .indentedCode, .fenceDelimiter: return "code"
        case .frontMatterLine, .frontMatterDelimiter: return "front"
        case .blockquote, .calloutTitle: return "quote"
        case .tableRow, .tableDelimiter: return "table"
        default:
            return line.quoteDepth > 0 ? "quote" : nil
        }
    }

    private static func decoration(for line: MDLine) -> DecorationKind? {
        switch line.kind {
        case .codeLine, .indentedCode, .fenceDelimiter: return .codeBlock
        case .frontMatterLine, .frontMatterDelimiter: return .frontMatter
        case .thematicBreak: return .thematicBreak
        case .tableRow, .tableDelimiter: return .table
        case .calloutTitle(let kind): return .callout(kind: kind)
        case .blockquote: return .blockquote(depth: line.quoteDepth)
        default:
            return line.quoteDepth > 0 ? .blockquote(depth: line.quoteDepth) : nil
        }
    }

    /// Marks lines that consist of nothing but an image, so they can be drawn
    /// rather than written out.
    private static func detectBlockImages(_ lines: inout [MDLine], text: Scan) {
        for index in lines.indices {
            switch lines[index].kind {
            case .paragraph, .blockquote, .listItem:
                lines[index].blockImage = blockImage(text, lines[index].contentRange)
            default:
                continue
            }
        }
    }

    /// Builds the reference link table, keyed by lowercased label.
    private static func collectDefinitions(_ lines: [MDLine], text: Scan) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines where line.kind == .linkDefinition {
            guard line.markerRange.length > 2 else { continue }
            let label = text.substring(
                with: NSRange(location: line.markerRange.location + 1,
                              length: line.markerRange.length - 3))
            guard line.contentRange.length > 0 else { continue }
            let destination = text.substring(with: line.contentRange)
                .trimmingCharacters(in: .whitespaces)
            result[label.lowercased()] = destination
        }
        return result
    }

    // MARK: - Inline pass

    private static func scanInlines(_ lines: inout [MDLine], text: Scan) {
        for index in lines.indices {
            let line = lines[index]
            switch line.kind {
            case .codeLine, .indentedCode, .frontMatterLine, .frontMatterDelimiter,
                 .thematicBreak, .setextUnderline, .linkDefinition,
                 // Emphasis and links change glyph widths, which would pull a
                 // monospace table's columns apart. Cells stay as written.
                 .tableRow, .tableDelimiter:
                continue
            default:
                break
            }
            guard line.contentRange.length > 0 else { continue }
            var tokens = InlineScanner.scan(text, range: line.contentRange)

            if case .listItem(_, let task) = line.kind, let task {
                if let checkbox = taskCheckbox(text, line.contentRange.location, NSMaxRange(line.contentRange)) {
                    let range = NSRange(location: line.contentRange.location,
                                        length: checkbox.end - line.contentRange.location)
                    tokens.removeAll { NSIntersectionRange($0.range, range).length > 0 }
                    tokens.append(InlineToken(range: range, kind: .taskMarker(task)))
                }
            }

            if case .calloutTitle(let kind) = line.kind {
                if let callout = calloutLabel(text, line.contentRange.location, NSMaxRange(line.contentRange)) {
                    let range = NSRange(location: line.contentRange.location,
                                        length: callout.end - line.contentRange.location)
                    tokens.removeAll { NSIntersectionRange($0.range, range).length > 0 }
                    tokens.append(InlineToken(range: range, kind: .calloutLabel(kind)))
                }
            }

            tokens.sort { $0.range.location < $1.range.location }
            lines[index].inlines = tokens
        }
    }

    // MARK: - Small scanners

    static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }
    static func isNewline(_ c: unichar) -> Bool { c == 10 || c == 13 }
    static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private static func skipSpaces(_ text: Scan, _ start: Int, _ end: Int) -> Int {
        var i = start
        while i < end, isSpace(text.chr(i)) { i += 1 }
        return i
    }

    private static func isBlank(_ text: Scan, _ start: Int, _ end: Int) -> Bool {
        var i = start
        while i < end {
            if !isSpace(text.chr(i)) { return false }
            i += 1
        }
        return true
    }

    /// True when the run starting at `start` is at least `minimum` repeats of `char`
    /// followed only by spaces.
    private static func isFence(_ text: Scan, _ start: Int, _ end: Int, char: unichar, minimum: Int) -> Bool {
        var i = start
        var count = 0
        while i < end, text.chr(i) == char { count += 1; i += 1 }
        guard count >= minimum else { return false }
        return isBlank(text, i, end)
    }

    private struct Fence {
        let char: unichar
        let length: Int
        let markerEnd: Int
        let language: String?
    }

    private static func fenceOpener(_ text: Scan, _ start: Int, _ end: Int) -> Fence? {
        guard start < end else { return nil }
        let c = text.chr(start)
        guard c == 96 || c == 126 else { return nil }  // ` or ~
        var i = start
        var count = 0
        while i < end, text.chr(i) == c { count += 1; i += 1 }
        guard count >= 3 else { return nil }
        let infoStart = skipSpaces(text, i, end)
        var infoEnd = infoStart
        while infoEnd < end, !isSpace(text.chr(infoEnd)) { infoEnd += 1 }
        let language = infoEnd > infoStart
            ? text.substring(with: NSRange(location: infoStart, length: infoEnd - infoStart))
            : nil
        return Fence(char: c, length: count, markerEnd: i, language: language)
    }

    private static func setextLevel(_ text: Scan, _ start: Int, _ end: Int) -> Int? {
        guard start < end else { return nil }
        let c = text.chr(start)
        guard c == 61 || c == 45 else { return nil }  // = or -
        var i = start
        var count = 0
        while i < end, text.chr(i) == c { count += 1; i += 1 }
        guard isBlank(text, i, end) else { return nil }
        // Only `===` makes a heading. `---` under a paragraph is a setext H2 in
        // CommonMark, but in a live editor that means typing a horizontal rule
        // silently promotes the line above it, which is a trap. Documents that
        // use it are converted to `##` on open by SetextNormalizer, so nothing
        // is lost.
        return c == 61 && count >= 1 ? 1 : nil
    }

    private static func isThematicBreak(_ text: Scan, _ start: Int, _ end: Int) -> Bool {
        guard start < end else { return false }
        let c = text.chr(start)
        guard c == 45 || c == 42 || c == 95 else { return false }  // - * _
        var i = start
        var count = 0
        while i < end {
            let ch = text.chr(i)
            if ch == c { count += 1 } else if !isSpace(ch) { return false }
            i += 1
        }
        return count >= 3
    }

    private struct Heading {
        let level: Int
        let markerEnd: Int
        let contentStart: Int
    }

    private static func atxHeading(_ text: Scan, _ start: Int, _ end: Int) -> Heading? {
        var i = start
        var level = 0
        while i < end, text.chr(i) == 35, level < 7 {  // '#'
            level += 1
            i += 1
        }
        guard level >= 1, level <= 6 else { return nil }
        guard i == end || isSpace(text.chr(i)) else { return nil }
        let contentStart = skipSpaces(text, i, end)
        return Heading(level: level, markerEnd: i, contentStart: contentStart)
    }

    private struct ListMarker {
        let ordered: Bool
        let markerEnd: Int
        let contentStart: Int
    }

    private static func listMarker(_ text: Scan, _ start: Int, _ end: Int) -> ListMarker? {
        guard start < end else { return nil }
        let c = text.chr(start)

        if c == 45 || c == 43 || c == 42 {  // - + *
            let next = start + 1
            guard next == end || isSpace(text.chr(next)) else { return nil }
            let contentStart = skipSpaces(text, next, end)
            return ListMarker(ordered: false, markerEnd: next, contentStart: contentStart)
        }

        if isDigit(c) {
            var i = start
            var digits = 0
            while i < end, isDigit(text.chr(i)), digits < 9 { i += 1; digits += 1 }
            guard i < end else { return nil }
            let delimiter = text.chr(i)
            guard delimiter == 46 || delimiter == 41 else { return nil }  // . or )
            i += 1
            guard i == end || isSpace(text.chr(i)) else { return nil }
            let contentStart = skipSpaces(text, i, end)
            return ListMarker(ordered: true, markerEnd: i, contentStart: contentStart)
        }

        return nil
    }

    private struct Checkbox {
        let state: TaskState
        let end: Int
    }

    private static func taskCheckbox(_ text: Scan, _ start: Int, _ end: Int) -> Checkbox? {
        guard start + 2 < end else { return nil }
        guard text.chr(start) == 91 else { return nil }  // '['
        let inner = text.chr(start + 1)
        guard text.chr(start + 2) == 93 else { return nil }  // ']'
        let state: TaskState
        switch inner {
        case 32: state = .open
        case 120, 88: state = .done  // x or X
        default: return nil
        }
        var after = start + 3
        guard after == end || isSpace(text.chr(after)) else { return nil }
        after = skipSpaces(text, after, end)
        return Checkbox(state: state, end: after)
    }

    private struct Callout {
        let kind: CalloutKind?
        let end: Int
    }

    /// Matches `[!NOTE]` at `start`, returning the index just past the closing bracket.
    private static func calloutLabel(_ text: Scan, _ start: Int, _ end: Int) -> Callout? {
        guard start + 2 < end else { return nil }
        guard text.chr(start) == 91, text.chr(start + 1) == 33 else { return nil }  // '[!'
        var i = start + 2
        while i < end, text.chr(i) != 93 { i += 1 }
        guard i < end else { return nil }
        let label = text.substring(with: NSRange(location: start + 2, length: i - start - 2)).uppercased()
        return Callout(kind: CalloutKind(rawValue: label), end: i + 1)
    }

    private struct Footnote {
        let markerEnd: Int
    }

    private static func footnoteDefinition(_ text: Scan, _ start: Int, _ end: Int) -> Footnote? {
        guard start + 3 < end else { return nil }
        guard text.chr(start) == 91, text.chr(start + 1) == 94 else { return nil }  // '[^'
        var i = start + 2
        while i < end, text.chr(i) != 93 { i += 1 }
        guard i + 1 < end, text.chr(i + 1) == 58 else { return nil }  // ']:'
        return Footnote(markerEnd: i + 2)
    }

    private struct LinkDefinition {
        let markerEnd: Int
        let label: String
    }

    /// Matches `[label]:` at the start of a line. Footnote definitions start
    /// `[^`, and are matched before this, so they are not swallowed here.
    private static func linkDefinition(_ text: Scan, _ start: Int, _ end: Int) -> LinkDefinition? {
        guard start + 2 < end, text.chr(start) == 91 else { return nil }  // '['
        guard text.chr(start + 1) != 94 else { return nil }               // not '[^'
        var i = start + 1
        while i < end, text.chr(i) != 93 {
            if text.chr(i) == 91 { return nil }
            i += 1
        }
        guard i < end, i > start + 1, i + 1 < end, text.chr(i + 1) == 58 else { return nil }
        let label = text.substring(with: NSRange(location: start + 1, length: i - start - 1))
        // A destination has to follow, otherwise this is ordinary prose.
        guard skipSpaces(text, i + 2, end) < end else { return nil }
        return LinkDefinition(markerEnd: i + 2, label: label)
    }

    /// Matches a line whose entire content is one image.
    private static func blockImage(_ text: Scan, _ range: NSRange) -> BlockImage? {
        var start = range.location
        var end = NSMaxRange(range)
        while start < end, isSpace(text.chr(start)) { start += 1 }
        while end > start, isSpace(text.chr(end - 1)) { end -= 1 }
        guard end - start > 4 else { return nil }
        guard text.chr(start) == 33, text.chr(start + 1) == 91 else { return nil }  // '!['

        var i = start + 2
        var depth = 1
        while i < end, depth > 0 {
            let c = text.chr(i)
            if c == 91 { depth += 1 }
            if c == 93 { depth -= 1; if depth == 0 { break } }
            i += 1
        }
        guard i < end, depth == 0 else { return nil }
        let altRange = NSRange(location: start + 2, length: i - start - 2)

        guard i + 1 < end, text.chr(i + 1) == 40 else { return nil }  // '('
        var j = i + 2
        var parens = 1
        while j < end, parens > 0 {
            let c = text.chr(j)
            if c == 40 { parens += 1 }
            if c == 41 { parens -= 1; if parens == 0 { break } }
            j += 1
        }
        guard j < end, parens == 0 else { return nil }
        // The closing paren has to be the last thing on the line.
        guard j == end - 1 else { return nil }

        let destination = text.substring(
            with: NSRange(location: i + 2, length: j - i - 2))
        return BlockImage(
            destination: destination,
            altRange: altRange,
            range: NSRange(location: start, length: end - start))
    }

    private static func isHTMLBlockStart(_ text: Scan, _ start: Int, _ end: Int) -> Bool {
        guard start + 1 < end else { return false }
        let next = text.chr(start + 1)
        // <tag, </tag, <!-- and <!DOCTYPE all count.
        return (next >= 97 && next <= 122) || (next >= 65 && next <= 90) || next == 47 || next == 33
    }

    static func isEscaped(_ text: Scan, _ index: Int, from start: Int) -> Bool {
        var backslashes = 0
        var i = index - 1
        while i >= start, text.chr(i) == 92 {  // '\'
            backslashes += 1
            i -= 1
        }
        return backslashes % 2 == 1
    }
}

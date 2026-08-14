import Foundation

/// A line-oriented Markdown scanner.
///
/// It is deliberately not a full CommonMark implementation: Quill never converts
/// the document to HTML, it only needs to know what each line *is* so it can be
/// styled and indented. That makes a single left-to-right pass enough, and keeps
/// re-parsing cheap enough to run on every keystroke.
enum MarkdownParser {

    static func parse(_ text: NSString) -> ParsedDocument {
        var lines = splitLines(text)
        guard !lines.isEmpty else { return ParsedDocument(lines: []) }

        classify(&lines, text: text)
        detectSetextHeadings(&lines, text: text)
        detectTables(&lines, text: text)
        assignBlocks(&lines)
        scanInlines(&lines, text: text)

        return ParsedDocument(lines: lines)
    }

    // MARK: - Line splitting

    private static func splitLines(_ text: NSString) -> [MDLine] {
        var result: [MDLine] = []
        let length = text.length
        var location = 0
        var number = 0

        while location <= length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                              for: NSRange(location: location, length: 0))

            result.append(MDLine(
                number: number,
                range: NSRange(location: start, length: contentsEnd - start),
                fullRange: NSRange(location: start, length: end - start)
            ))
            number += 1

            if end == location {
                // getLineStart made no progress: we are past the final newline.
                break
            }
            location = end
            if location == length {
                // A trailing newline means there is one more, empty, line.
                if length > 0, isNewline(text.character(at: length - 1)) {
                    result.append(MDLine(
                        number: number,
                        range: NSRange(location: length, length: 0),
                        fullRange: NSRange(location: length, length: 0)
                    ))
                }
                break
            }
        }
        return result
    }

    // MARK: - Structural classification

    private static func classify(_ lines: inout [MDLine], text: NSString) {
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
                while cursor < end, isSpace(text.character(at: cursor)), indent < 3 {
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
                let c = text.character(at: cursor)
                if c == 32 { indentColumns += 1 } else if c == 9 { indentColumns += 4 } else { break }
                cursor += 1
            }
            let firstNonSpace = cursor

            // --- Blockquote markers ----------------------------------------------
            var quoteDepth = 0
            var markerEnd = firstNonSpace
            while cursor < end, text.character(at: cursor) == 62 {  // '>'
                quoteDepth += 1
                cursor += 1
                markerEnd = cursor
                while cursor < end, isSpace(text.character(at: cursor)) { cursor += 1 }
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

            // --- Definition list item ---------------------------------------------------------------
            if quoteDepth == 0, innerStart < end, text.character(at: innerStart) == 58,  // ':'
                innerStart + 1 < end, isSpace(text.character(at: innerStart + 1)) {
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
            if innerStart < end, text.character(at: innerStart) == 60, isHTMLBlockStart(text, innerStart, end) {
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

    // MARK: - Setext headings

    /// Turns the paragraph lines directly above a `===` / `---` underline into a heading.
    private static func detectSetextHeadings(_ lines: inout [MDLine], text: NSString) {
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

    // MARK: - Tables

    private static func detectTables(_ lines: inout [MDLine], text: NSString) {
        var index = 0
        while index < lines.count - 1 {
            defer { index += 1 }
            let line = lines[index]
            guard !line.kind.isCode, line.kind != .frontMatterLine,
                  line.kind != .frontMatterDelimiter,
                  containsPipe(text, line.contentRange) else { continue }
            guard isTableDelimiterRow(text, lines[index + 1].range) else { continue }

            lines[index].kind = .tableHeader
            lines[index + 1].kind = .tableDelimiter
            lines[index + 1].contentRange = lines[index + 1].range
            lines[index + 1].markerRange = NSRange(location: lines[index + 1].range.location, length: 0)
            lines[index + 1].gapRange = NSRange(location: lines[index + 1].range.location, length: 0)

            var row = index + 2
            while row < lines.count,
                  !lines[row].kind.isCode,
                  containsPipe(text, lines[row].range),
                  !isBlank(text, lines[row].range.location, NSMaxRange(lines[row].range)) {
                lines[row].kind = .tableRow
                lines[row].contentRange = lines[row].range
                lines[row].markerRange = NSRange(location: lines[row].range.location, length: 0)
                lines[row].gapRange = NSRange(location: lines[row].range.location, length: 0)
                row += 1
            }
            index = row - 1
        }
    }

    // MARK: - Block grouping

    private static func assignBlocks(_ lines: inout [MDLine]) {
        var blockID = 0
        var previousSignature: String?

        for index in lines.indices {
            let signature = groupSignature(lines[index])
            if signature == nil || signature != previousSignature {
                blockID += 1
            }
            previousSignature = signature
            lines[index].blockID = blockID
            lines[index].decoration = decoration(for: lines[index])
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
        case .tableHeader, .tableDelimiter, .tableRow: return "table"
        case .blockquote, .calloutTitle: return "quote"
        default:
            return line.quoteDepth > 0 ? "quote" : nil
        }
    }

    private static func decoration(for line: MDLine) -> DecorationKind? {
        switch line.kind {
        case .codeLine, .indentedCode, .fenceDelimiter: return .codeBlock
        case .frontMatterLine, .frontMatterDelimiter: return .frontMatter
        case .tableHeader, .tableDelimiter, .tableRow: return .table
        case .thematicBreak: return .thematicBreak
        case .calloutTitle(let kind): return .callout(kind: kind)
        case .blockquote: return .blockquote(depth: line.quoteDepth)
        default:
            return line.quoteDepth > 0 ? .blockquote(depth: line.quoteDepth) : nil
        }
    }

    // MARK: - Inline pass

    private static func scanInlines(_ lines: inout [MDLine], text: NSString) {
        for index in lines.indices {
            let line = lines[index]
            switch line.kind {
            case .codeLine, .indentedCode, .frontMatterLine, .frontMatterDelimiter,
                 .thematicBreak, .setextUnderline:
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

            if line.kind.isTable {
                let content = line.contentRange
                var cursor = content.location
                let end = NSMaxRange(content)
                while cursor < end {
                    if text.character(at: cursor) == 124,  // '|'
                       !isEscaped(text, cursor, from: content.location) {
                        let pipe = NSRange(location: cursor, length: 1)
                        tokens.removeAll { NSIntersectionRange($0.range, pipe).length > 0 }
                        tokens.append(InlineToken(range: pipe, kind: .tablePipe))
                    }
                    cursor += 1
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

    private static func skipSpaces(_ text: NSString, _ start: Int, _ end: Int) -> Int {
        var i = start
        while i < end, isSpace(text.character(at: i)) { i += 1 }
        return i
    }

    private static func isBlank(_ text: NSString, _ start: Int, _ end: Int) -> Bool {
        var i = start
        while i < end {
            if !isSpace(text.character(at: i)) { return false }
            i += 1
        }
        return true
    }

    /// True when the run starting at `start` is at least `minimum` repeats of `char`
    /// followed only by spaces.
    private static func isFence(_ text: NSString, _ start: Int, _ end: Int, char: unichar, minimum: Int) -> Bool {
        var i = start
        var count = 0
        while i < end, text.character(at: i) == char { count += 1; i += 1 }
        guard count >= minimum else { return false }
        return isBlank(text, i, end)
    }

    private struct Fence {
        let char: unichar
        let length: Int
        let markerEnd: Int
        let language: String?
    }

    private static func fenceOpener(_ text: NSString, _ start: Int, _ end: Int) -> Fence? {
        guard start < end else { return nil }
        let c = text.character(at: start)
        guard c == 96 || c == 126 else { return nil }  // ` or ~
        var i = start
        var count = 0
        while i < end, text.character(at: i) == c { count += 1; i += 1 }
        guard count >= 3 else { return nil }
        let infoStart = skipSpaces(text, i, end)
        var infoEnd = infoStart
        while infoEnd < end, !isSpace(text.character(at: infoEnd)) { infoEnd += 1 }
        let language = infoEnd > infoStart
            ? text.substring(with: NSRange(location: infoStart, length: infoEnd - infoStart))
            : nil
        return Fence(char: c, length: count, markerEnd: i, language: language)
    }

    private static func setextLevel(_ text: NSString, _ start: Int, _ end: Int) -> Int? {
        guard start < end else { return nil }
        let c = text.character(at: start)
        guard c == 61 || c == 45 else { return nil }  // = or -
        var i = start
        var count = 0
        while i < end, text.character(at: i) == c { count += 1; i += 1 }
        guard isBlank(text, i, end) else { return nil }
        if c == 61 { return count >= 1 ? 1 : nil }
        // `---` is ambiguous with a thematic break; detectSetextHeadings resolves it.
        return count >= 2 ? 2 : nil
    }

    private static func isThematicBreak(_ text: NSString, _ start: Int, _ end: Int) -> Bool {
        guard start < end else { return false }
        let c = text.character(at: start)
        guard c == 45 || c == 42 || c == 95 else { return false }  // - * _
        var i = start
        var count = 0
        while i < end {
            let ch = text.character(at: i)
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

    private static func atxHeading(_ text: NSString, _ start: Int, _ end: Int) -> Heading? {
        var i = start
        var level = 0
        while i < end, text.character(at: i) == 35, level < 7 {  // '#'
            level += 1
            i += 1
        }
        guard level >= 1, level <= 6 else { return nil }
        guard i == end || isSpace(text.character(at: i)) else { return nil }
        let contentStart = skipSpaces(text, i, end)
        return Heading(level: level, markerEnd: i, contentStart: contentStart)
    }

    private struct ListMarker {
        let ordered: Bool
        let markerEnd: Int
        let contentStart: Int
    }

    private static func listMarker(_ text: NSString, _ start: Int, _ end: Int) -> ListMarker? {
        guard start < end else { return nil }
        let c = text.character(at: start)

        if c == 45 || c == 43 || c == 42 {  // - + *
            let next = start + 1
            guard next == end || isSpace(text.character(at: next)) else { return nil }
            let contentStart = skipSpaces(text, next, end)
            return ListMarker(ordered: false, markerEnd: next, contentStart: contentStart)
        }

        if isDigit(c) {
            var i = start
            var digits = 0
            while i < end, isDigit(text.character(at: i)), digits < 9 { i += 1; digits += 1 }
            guard i < end else { return nil }
            let delimiter = text.character(at: i)
            guard delimiter == 46 || delimiter == 41 else { return nil }  // . or )
            i += 1
            guard i == end || isSpace(text.character(at: i)) else { return nil }
            let contentStart = skipSpaces(text, i, end)
            return ListMarker(ordered: true, markerEnd: i, contentStart: contentStart)
        }

        return nil
    }

    private struct Checkbox {
        let state: TaskState
        let end: Int
    }

    private static func taskCheckbox(_ text: NSString, _ start: Int, _ end: Int) -> Checkbox? {
        guard start + 2 < end else { return nil }
        guard text.character(at: start) == 91 else { return nil }  // '['
        let inner = text.character(at: start + 1)
        guard text.character(at: start + 2) == 93 else { return nil }  // ']'
        let state: TaskState
        switch inner {
        case 32: state = .open
        case 120, 88: state = .done  // x or X
        default: return nil
        }
        var after = start + 3
        guard after == end || isSpace(text.character(at: after)) else { return nil }
        after = skipSpaces(text, after, end)
        return Checkbox(state: state, end: after)
    }

    private struct Callout {
        let kind: CalloutKind?
        let end: Int
    }

    /// Matches `[!NOTE]` at `start`, returning the index just past the closing bracket.
    private static func calloutLabel(_ text: NSString, _ start: Int, _ end: Int) -> Callout? {
        guard start + 2 < end else { return nil }
        guard text.character(at: start) == 91, text.character(at: start + 1) == 33 else { return nil }  // '[!'
        var i = start + 2
        while i < end, text.character(at: i) != 93 { i += 1 }
        guard i < end else { return nil }
        let label = text.substring(with: NSRange(location: start + 2, length: i - start - 2)).uppercased()
        return Callout(kind: CalloutKind(rawValue: label), end: i + 1)
    }

    private struct Footnote {
        let markerEnd: Int
    }

    private static func footnoteDefinition(_ text: NSString, _ start: Int, _ end: Int) -> Footnote? {
        guard start + 3 < end else { return nil }
        guard text.character(at: start) == 91, text.character(at: start + 1) == 94 else { return nil }  // '[^'
        var i = start + 2
        while i < end, text.character(at: i) != 93 { i += 1 }
        guard i + 1 < end, text.character(at: i + 1) == 58 else { return nil }  // ']:'
        return Footnote(markerEnd: i + 2)
    }

    private static func isHTMLBlockStart(_ text: NSString, _ start: Int, _ end: Int) -> Bool {
        guard start + 1 < end else { return false }
        let next = text.character(at: start + 1)
        // <tag, </tag, <!-- and <!DOCTYPE all count.
        return (next >= 97 && next <= 122) || (next >= 65 && next <= 90) || next == 47 || next == 33
    }

    private static func containsPipe(_ text: NSString, _ range: NSRange) -> Bool {
        var i = range.location
        let end = NSMaxRange(range)
        while i < end {
            if text.character(at: i) == 124, !isEscaped(text, i, from: range.location) { return true }
            i += 1
        }
        return false
    }

    /// A delimiter row is made only of pipes, dashes, colons and spaces, and has
    /// at least one dash and one pipe.
    private static func isTableDelimiterRow(_ text: NSString, _ range: NSRange) -> Bool {
        var i = range.location
        let end = NSMaxRange(range)
        var dashes = 0
        var pipes = 0
        var sawOther = false
        while i < end {
            switch text.character(at: i) {
            case 45: dashes += 1
            case 124: pipes += 1
            case 58, 32, 9: break
            default: sawOther = true
            }
            i += 1
        }
        return !sawOther && dashes >= 1 && pipes >= 1
    }

    static func isEscaped(_ text: NSString, _ index: Int, from start: Int) -> Bool {
        var backslashes = 0
        var i = index - 1
        while i >= start, text.character(at: i) == 92 {  // '\'
            backslashes += 1
            i -= 1
        }
        return backslashes % 2 == 1
    }
}

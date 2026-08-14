import Foundation

/// Finds inline constructs inside a single line's content.
///
/// Emphasis matching is a pragmatic approximation of the CommonMark rules: an
/// opening delimiter run must be followed by a non-space, and its closer must be
/// preceded by a non-space. That handles real prose (including `snake_case`,
/// which is left alone) without the full flanking algorithm.
enum InlineScanner {

    private enum Char {
        static let backslash: unichar = 92
        static let backtick: unichar = 96
        static let asterisk: unichar = 42
        static let underscore: unichar = 95
        static let tilde: unichar = 126
        static let equals: unichar = 61
        static let bracketOpen: unichar = 91
        static let bracketClose: unichar = 93
        static let parenOpen: unichar = 40
        static let parenClose: unichar = 41
        static let bang: unichar = 33
        static let caret: unichar = 94
        static let angleOpen: unichar = 60
        static let angleClose: unichar = 62
        static let dollar: unichar = 36
        static let space: unichar = 32
        static let tab: unichar = 9
    }

    static func scan(_ text: NSString, range: NSRange) -> [InlineToken] {
        var tokens: [InlineToken] = []
        scan(text, from: range.location, to: NSMaxRange(range), depth: 0, into: &tokens)
        appendHardBreak(text, range: range, into: &tokens)
        return tokens
    }

    // MARK: - Main loop

    private static func scan(
        _ text: NSString, from start: Int, to end: Int, depth: Int, into tokens: inout [InlineToken]
    ) {
        guard depth < 6 else { return }  // guards against pathological nesting
        var i = start

        while i < end {
            let c = text.character(at: i)

            // Backslash escape: the backslash dims, the escaped character stays.
            if c == Char.backslash, i + 1 < end, isPunctuation(text.character(at: i + 1)) {
                tokens.append(InlineToken(range: NSRange(location: i, length: 1), kind: .syntax))
                tokens.append(InlineToken(range: NSRange(location: i + 1, length: 1), kind: .escape))
                i += 2
                continue
            }

            switch c {
            case Char.backtick:
                if let consumed = scanCodeSpan(text, i, end, into: &tokens) { i = consumed; continue }

            case Char.angleOpen:
                if let consumed = scanAngle(text, i, end, into: &tokens) { i = consumed; continue }

            case Char.bang:
                if i + 1 < end, text.character(at: i + 1) == Char.bracketOpen,
                   let consumed = scanLink(text, i, end, isImage: true, depth: depth, into: &tokens) {
                    i = consumed
                    continue
                }

            case Char.bracketOpen:
                if let consumed = scanFootnoteRef(text, i, end, into: &tokens) { i = consumed; continue }
                if let consumed = scanLink(text, i, end, isImage: false, depth: depth, into: &tokens) {
                    i = consumed
                    continue
                }

            case Char.dollar:
                if let consumed = scanMath(text, i, end, into: &tokens) { i = consumed; continue }

            case Char.asterisk, Char.underscore:
                if let consumed = scanEmphasis(text, i, end, char: c, depth: depth, into: &tokens) {
                    i = consumed
                    continue
                }

            case Char.tilde:
                if let consumed = scanPaired(
                    text, i, end, char: Char.tilde, count: 2, kind: .strikethrough,
                    depth: depth, into: &tokens) {
                    i = consumed
                    continue
                }

            case Char.equals:
                if let consumed = scanPaired(
                    text, i, end, char: Char.equals, count: 2, kind: .highlight,
                    depth: depth, into: &tokens) {
                    i = consumed
                    continue
                }

            default:
                break
            }

            i += 1
        }
    }

    // MARK: - Code spans

    private static func scanCodeSpan(
        _ text: NSString, _ start: Int, _ end: Int, into tokens: inout [InlineToken]
    ) -> Int? {
        var open = start
        while open < end, text.character(at: open) == Char.backtick { open += 1 }
        let ticks = open - start
        var i = open

        while i < end {
            if text.character(at: i) == Char.backtick {
                var close = i
                while close < end, text.character(at: close) == Char.backtick { close += 1 }
                if close - i == ticks {
                    tokens.append(InlineToken(range: NSRange(location: start, length: ticks), kind: .syntax))
                    if i > open {
                        tokens.append(InlineToken(range: NSRange(location: open, length: i - open), kind: .code))
                    }
                    tokens.append(InlineToken(range: NSRange(location: i, length: ticks), kind: .syntax))
                    return close
                }
                i = close
                continue
            }
            i += 1
        }
        return nil
    }

    // MARK: - Autolinks and raw HTML

    private static func scanAngle(
        _ text: NSString, _ start: Int, _ end: Int, into tokens: inout [InlineToken]
    ) -> Int? {
        var i = start + 1
        var sawColonOrAt = false
        while i < end {
            let c = text.character(at: i)
            if c == Char.space || c == Char.tab { break }
            if c == 58 || c == 64 { sawColonOrAt = true }  // ':' or '@'
            if c == Char.angleClose {
                if sawColonOrAt, i > start + 1 {
                    tokens.append(InlineToken(range: NSRange(location: start, length: 1), kind: .syntax))
                    tokens.append(InlineToken(
                        range: NSRange(location: start + 1, length: i - start - 1), kind: .autolink))
                    tokens.append(InlineToken(range: NSRange(location: i, length: 1), kind: .syntax))
                    return i + 1
                }
                break
            }
            i += 1
        }

        // Not an autolink; treat a well-formed `<tag …>` as raw HTML.
        var j = start + 1
        while j < end, text.character(at: j) != Char.angleClose {
            if text.character(at: j) == Char.angleOpen { return nil }
            j += 1
        }
        guard j < end else { return nil }
        tokens.append(InlineToken(range: NSRange(location: start, length: j - start + 1), kind: .html))
        return j + 1
    }

    // MARK: - Links and images

    private static func scanLink(
        _ text: NSString, _ start: Int, _ end: Int, isImage: Bool, depth: Int,
        into tokens: inout [InlineToken]
    ) -> Int? {
        let bracketStart = isImage ? start + 1 : start
        guard let bracketEnd = matchingBracket(text, bracketStart, end) else { return nil }

        let textStart = bracketStart + 1
        let openSyntax = NSRange(location: start, length: textStart - start)

        var cursor = bracketEnd + 1
        var tailTokens: [InlineToken] = []

        if cursor < end, text.character(at: cursor) == Char.parenOpen {
            // Inline destination: [text](url "title")
            guard let parenEnd = matchingParen(text, cursor, end) else { return nil }
            tailTokens.append(InlineToken(range: NSRange(location: bracketEnd, length: 2), kind: .syntax))
            if parenEnd > cursor + 1 {
                tailTokens.append(InlineToken(
                    range: NSRange(location: cursor + 1, length: parenEnd - cursor - 1), kind: .linkURL))
            }
            tailTokens.append(InlineToken(range: NSRange(location: parenEnd, length: 1), kind: .syntax))
            cursor = parenEnd + 1
        } else if cursor < end, text.character(at: cursor) == Char.bracketOpen {
            // Reference: [text][ref]
            guard let refEnd = matchingBracket(text, cursor, end) else { return nil }
            tailTokens.append(InlineToken(range: NSRange(location: bracketEnd, length: 2), kind: .syntax))
            if refEnd > cursor + 1 {
                tailTokens.append(InlineToken(
                    range: NSRange(location: cursor + 1, length: refEnd - cursor - 1), kind: .linkURL))
            }
            tailTokens.append(InlineToken(range: NSRange(location: refEnd, length: 1), kind: .syntax))
            cursor = refEnd + 1
        } else {
            // Shortcut reference: [text]
            tailTokens.append(InlineToken(range: NSRange(location: bracketEnd, length: 1), kind: .syntax))
            cursor = bracketEnd + 1
        }

        tokens.append(InlineToken(range: openSyntax, kind: .syntax))
        if bracketEnd > textStart {
            let inner = NSRange(location: textStart, length: bracketEnd - textStart)
            tokens.append(InlineToken(range: inner, kind: isImage ? .imageAlt : .linkText))
            if !isImage {
                scan(text, from: inner.location, to: NSMaxRange(inner), depth: depth + 1, into: &tokens)
            }
        }
        tokens.append(contentsOf: tailTokens)
        return cursor
    }

    private static func scanFootnoteRef(
        _ text: NSString, _ start: Int, _ end: Int, into tokens: inout [InlineToken]
    ) -> Int? {
        guard start + 2 < end, text.character(at: start + 1) == Char.caret else { return nil }
        var i = start + 2
        while i < end, text.character(at: i) != Char.bracketClose {
            if text.character(at: i) == Char.bracketOpen { return nil }
            i += 1
        }
        guard i < end else { return nil }
        // A definition (`[^1]: …`) is a block, handled by the line parser.
        if i + 1 < end, text.character(at: i + 1) == 58 { return nil }
        tokens.append(InlineToken(range: NSRange(location: start, length: i - start + 1), kind: .footnoteRef))
        return i + 1
    }

    // MARK: - Math

    private static func scanMath(
        _ text: NSString, _ start: Int, _ end: Int, into tokens: inout [InlineToken]
    ) -> Int? {
        var open = start
        while open < end, text.character(at: open) == Char.dollar, open - start < 2 { open += 1 }
        let count = open - start
        guard open < end, !isSpaceChar(text.character(at: open)) else { return nil }

        var i = open
        while i < end {
            if text.character(at: i) == Char.dollar,
               !MarkdownParser.isEscaped(text, i, from: start),
               !isSpaceChar(text.character(at: i - 1)) {
                var close = i
                while close < end, text.character(at: close) == Char.dollar, close - i < count { close += 1 }
                guard close - i == count else { i = close; continue }
                tokens.append(InlineToken(range: NSRange(location: start, length: count), kind: .syntax))
                tokens.append(InlineToken(range: NSRange(location: open, length: i - open), kind: .math))
                tokens.append(InlineToken(range: NSRange(location: i, length: count), kind: .syntax))
                return close
            }
            i += 1
        }
        return nil
    }

    // MARK: - Emphasis

    private static func scanEmphasis(
        _ text: NSString, _ start: Int, _ end: Int, char: unichar, depth: Int,
        into tokens: inout [InlineToken]
    ) -> Int? {
        var open = start
        while open < end, text.character(at: open) == char { open += 1 }
        let runLength = min(open - start, 3)

        let kind: InlineKind
        switch runLength {
        case 1: kind = .emphasis
        case 2: kind = .strong
        default: kind = .strongEmphasis
        }

        // `_` inside a word is an identifier, not emphasis.
        if char == Char.underscore, start > 0, isWordCharacter(text.character(at: start - 1)) {
            return nil
        }

        return scanPaired(text, start, end, char: char, count: runLength, kind: kind,
                          depth: depth, into: &tokens)
    }

    /// Matches a delimiter run of `count` copies of `char` with its closer, then
    /// recurses into the enclosed text.
    private static func scanPaired(
        _ text: NSString, _ start: Int, _ end: Int, char: unichar, count: Int,
        kind: InlineKind, depth: Int, into tokens: inout [InlineToken]
    ) -> Int? {
        var run = start
        while run < end, text.character(at: run) == char { run += 1 }
        guard run - start >= count else { return nil }

        let contentStart = start + count
        guard contentStart < end, !isSpaceChar(text.character(at: contentStart)) else { return nil }

        var i = contentStart
        while i < end {
            guard text.character(at: i) == char,
                  !MarkdownParser.isEscaped(text, i, from: start) else { i += 1; continue }

            var close = i
            while close < end, text.character(at: close) == char { close += 1 }
            guard close - i >= count, i > contentStart,
                  !isSpaceChar(text.character(at: i - 1)) else {
                i = close
                continue
            }

            let closeStart = close - count
            tokens.append(InlineToken(range: NSRange(location: start, length: count), kind: .syntax))
            let inner = NSRange(location: contentStart, length: closeStart - contentStart)
            if inner.length > 0 {
                tokens.append(InlineToken(range: inner, kind: kind))
                scan(text, from: inner.location, to: NSMaxRange(inner), depth: depth + 1, into: &tokens)
            }
            tokens.append(InlineToken(range: NSRange(location: closeStart, length: count), kind: .syntax))
            return close
        }
        return nil
    }

    // MARK: - Hard break

    private static func appendHardBreak(
        _ text: NSString, range: NSRange, into tokens: inout [InlineToken]
    ) {
        let end = NSMaxRange(range)
        guard end - range.location >= 2 else { return }
        var i = end
        var spaces = 0
        while i > range.location, text.character(at: i - 1) == Char.space {
            spaces += 1
            i -= 1
        }
        guard spaces >= 2 else { return }
        tokens.append(InlineToken(range: NSRange(location: end - spaces, length: spaces), kind: .hardBreak))
    }

    // MARK: - Bracket matching

    private static func matchingBracket(_ text: NSString, _ open: Int, _ end: Int) -> Int? {
        var level = 0
        var i = open
        while i < end {
            let c = text.character(at: i)
            if !MarkdownParser.isEscaped(text, i, from: open) {
                if c == Char.bracketOpen { level += 1 }
                if c == Char.bracketClose {
                    level -= 1
                    if level == 0 { return i }
                }
            }
            i += 1
        }
        return nil
    }

    private static func matchingParen(_ text: NSString, _ open: Int, _ end: Int) -> Int? {
        var level = 0
        var i = open
        while i < end {
            let c = text.character(at: i)
            if !MarkdownParser.isEscaped(text, i, from: open) {
                if c == Char.parenOpen { level += 1 }
                if c == Char.parenClose {
                    level -= 1
                    if level == 0 { return i }
                }
            }
            i += 1
        }
        return nil
    }

    // MARK: - Character classes

    private static func isSpaceChar(_ c: unichar) -> Bool { c == 32 || c == 9 }

    private static func isWordCharacter(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    private static func isPunctuation(_ c: unichar) -> Bool {
        switch c {
        case 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
             58, 59, 60, 61, 62, 63, 64,
             91, 92, 93, 94, 95, 96,
             123, 124, 125, 126:
            return true
        default:
            return false
        }
    }
}

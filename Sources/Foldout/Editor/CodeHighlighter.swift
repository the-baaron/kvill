import Foundation

/// A deliberately generic tokeniser for fenced code blocks.
///
/// Foldout is a Markdown editor, not an IDE, so this does not try to be correct per
/// language. It recognises the four things that carry most of the visual signal
/// across nearly every language: comments, strings, numbers and keywords.
enum CodeHighlighter {

    enum TokenKind {
        case comment
        case string
        case number
        case keyword
    }

    struct Token {
        let range: NSRange
        let kind: TokenKind
    }

    /// Languages where `#` starts a comment rather than a preprocessor directive.
    private static let hashComment: Set<String> = [
        "python", "py", "ruby", "rb", "sh", "bash", "zsh", "shell", "yaml", "yml",
        "toml", "perl", "r", "makefile", "make", "dockerfile", "conf", "ini", "nix",
    ]

    private static let keywords: Set<String> = [
        // Control flow shared across most C-family and scripting languages.
        "if", "else", "elif", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "return", "goto", "yield", "await", "async", "throw",
        "throws", "try", "catch", "finally", "guard", "defer", "match", "when",
        // Declarations.
        "func", "function", "fn", "def", "let", "var", "const", "class", "struct",
        "enum", "protocol", "interface", "trait", "impl", "extension", "type",
        "typedef", "namespace", "module", "package", "import", "from", "export",
        "require", "include", "use", "using", "public", "private", "internal",
        "protected", "static", "final", "abstract", "override", "mutating",
        "extends", "implements", "new", "delete", "this", "self", "super",
        // Values and types.
        "true", "false", "null", "nil", "none", "None", "True", "False", "undefined",
        "int", "float", "double", "bool", "boolean", "string", "str", "char", "void",
        "auto", "unsigned", "signed", "long", "short", "byte", "any", "unknown",
        "and", "or", "not", "in", "is", "as", "with", "pass", "lambda", "where",
        "select", "insert", "update", "delete", "where", "from",
    ]

    static func tokens(_ text: NSString, range: NSRange, language: String?) -> [Token] {
        var result: [Token] = []
        let lang = language?.lowercased() ?? ""
        let hashIsComment = hashComment.contains(lang)

        var i = range.location
        let end = NSMaxRange(range)

        while i < end {
            let c = text.character(at: i)

            // Line comments: // and #, plus block comments /* … */
            if c == 47, i + 1 < end {  // '/'
                let next = text.character(at: i + 1)
                if next == 47 {
                    let stop = lineEnd(text, i, end)
                    result.append(Token(range: NSRange(location: i, length: stop - i), kind: .comment))
                    i = stop
                    continue
                }
                if next == 42 {  // '*'
                    var j = i + 2
                    while j + 1 < end, !(text.character(at: j) == 42 && text.character(at: j + 1) == 47) { j += 1 }
                    let stop = min(j + 2, end)
                    result.append(Token(range: NSRange(location: i, length: stop - i), kind: .comment))
                    i = stop
                    continue
                }
            }

            if hashIsComment, c == 35 {  // '#'
                let stop = lineEnd(text, i, end)
                result.append(Token(range: NSRange(location: i, length: stop - i), kind: .comment))
                i = stop
                continue
            }

            if c == 45, i + 1 < end, text.character(at: i + 1) == 45, lang == "sql" || lang == "lua" {
                let stop = lineEnd(text, i, end)
                result.append(Token(range: NSRange(location: i, length: stop - i), kind: .comment))
                i = stop
                continue
            }

            // Strings. Unterminated quotes stop at end of line so one stray quote
            // does not paint the rest of the block.
            if c == 34 || c == 39 || c == 96 {  // " ' `
                var j = i + 1
                let limit = c == 96 ? end : lineEnd(text, i, end)
                while j < limit {
                    let ch = text.character(at: j)
                    if ch == 92 { j += 2; continue }  // backslash escape
                    if ch == c { j += 1; break }
                    j += 1
                }
                let stop = min(j, end)
                result.append(Token(range: NSRange(location: i, length: stop - i), kind: .string))
                i = stop
                continue
            }

            // Numbers, including hex and decimals.
            if isDigit(c), !isIdentifierChar(i > range.location ? text.character(at: i - 1) : 32) {
                var j = i
                while j < end, isNumberChar(text.character(at: j)) { j += 1 }
                result.append(Token(range: NSRange(location: i, length: j - i), kind: .number))
                i = j
                continue
            }

            // Identifiers, checked against the keyword set.
            if isIdentifierStart(c) {
                var j = i
                while j < end, isIdentifierChar(text.character(at: j)) { j += 1 }
                let word = text.substring(with: NSRange(location: i, length: j - i))
                if keywords.contains(word) {
                    result.append(Token(range: NSRange(location: i, length: j - i), kind: .keyword))
                }
                i = j
                continue
            }

            i += 1
        }
        return result
    }

    private static func lineEnd(_ text: NSString, _ from: Int, _ end: Int) -> Int {
        var i = from
        while i < end, text.character(at: i) != 10 { i += 1 }
        return i
    }

    private static func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

    private static func isNumberChar(_ c: unichar) -> Bool {
        isDigit(c) || c == 46 || c == 95
            || (c >= 97 && c <= 102) || (c >= 65 && c <= 70) || c == 120 || c == 88
    }

    private static func isIdentifierStart(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    private static func isIdentifierChar(_ c: unichar) -> Bool {
        isIdentifierStart(c) || isDigit(c)
    }
}

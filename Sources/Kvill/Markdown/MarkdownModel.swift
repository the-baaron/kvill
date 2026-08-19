import Foundation

/// What a single line is, structurally.
enum BlockKind: Equatable {
    case blank
    case paragraph
    case heading(level: Int)
    /// A `===` or `---` underline that promotes the paragraph above it.
    case setextUnderline(level: Int)
    /// The opening or closing ``` line of a fenced block.
    case fenceDelimiter(language: String?)
    /// A line inside a fenced or indented code block.
    case codeLine
    case indentedCode
    case listItem(ordered: Bool, task: TaskState?)
    case blockquote
    /// The `> [!NOTE]` line that opens a GitHub alert.
    case calloutTitle(kind: CalloutKind?)
    case thematicBreak
    case frontMatterDelimiter
    case frontMatterLine
    case footnoteDefinition
    /// A `[label]: destination` line that gives a reference link its target.
    case linkDefinition
    case definition
    case htmlLine
    /// A `| cell | cell |` row. The header is the row above the delimiter.
    case tableRow(header: Bool)
    /// The `| --- | :-: |` row that separates the header and sets alignment.
    case tableDelimiter

    var isHeading: Bool {
        if case .heading = self { return true }
        return false
    }

    var isCode: Bool {
        switch self {
        case .codeLine, .indentedCode, .fenceDelimiter: return true
        default: return false
        }
    }

    /// True for any line of a table. Table lines are shown as aligned source, so
    /// they opt out of inline styling, which would change glyph widths and pull
    /// the columns apart.
    var isTable: Bool {
        switch self {
        case .tableRow, .tableDelimiter: return true
        default: return false
        }
    }

    /// Whether this line is the top or bottom edge of a block the editor draws a
    /// panel around.
    ///
    /// Its marker stays inside the panel rather than hanging in the gutter. The
    /// panel starts left of the text column, so a hanging ``` or --- lands on
    /// the panel's border and, at the corners, through the curve of it.
    var opensADrawnPanel: Bool {
        switch self {
        case .fenceDelimiter, .frontMatterDelimiter: return true
        default: return false
        }
    }
}

enum TaskState: Equatable {
    case open
    case done
}

/// Background treatment drawn behind a run of lines.
enum DecorationKind: Equatable {
    case codeBlock
    case blockquote(depth: Int)
    case callout(kind: CalloutKind?)
    case frontMatter
    case thematicBreak
    case table
}

/// One parsed line. Ranges are UTF-16 offsets into the whole document, which is
/// what NSTextStorage wants, so no conversion happens during styling.
struct MDLine {
    var number: Int
    /// The line's characters, not including its newline.
    var range: NSRange
    /// The line including its trailing newline, if any.
    var fullRange: NSRange

    var kind: BlockKind = .blank

    /// Leading syntax pulled into the gutter, e.g. `##`, `>`, `- `, ` ``` `.
    var markerRange = NSRange(location: 0, length: 0)
    /// Whitespace between the marker and the content. Kerned so the content
    /// lands on the column no matter how wide the marker is.
    var gapRange = NSRange(location: 0, length: 0)
    /// Everything after the marker and gap.
    var contentRange = NSRange(location: 0, length: 0)

    var quoteDepth = 0
    var listDepth = 0
    /// Groups consecutive lines that share one background decoration.
    var blockID = 0
    /// Groups consecutive non-blank lines. Focus mode works on these, so a
    /// wrapped sentence and the lines around it stay lit as one paragraph.
    var paragraphID = 0
    var decoration: DecorationKind?
    /// Inline runs found inside `contentRange`.
    var inlines: [InlineToken] = []
    /// Language tag on a fence, carried to every line of the block.
    var language: String?
    /// Set when the line is nothing but an image, which is drawn in place of
    /// the Markdown that describes it.
    var blockImage: BlockImage?
    /// First and last line of their block, so a block can be given space above
    /// and below it without every line inside it getting the same.
    var isBlockStart = false
    var isBlockEnd = false
    /// Characters in the longest row of the table this line belongs to. The
    /// table is monospace, so this is its width in one number, and the styler
    /// can size it to the measure without laying anything out.
    var tableWidth = 0

    var hasMarker: Bool { markerRange.length > 0 }
}

/// Inline constructs. `syntax` variants are the characters that get dimmed;
/// the rest carry visual styling.
enum InlineKind: Equatable {
    case syntax
    case strong
    case emphasis
    case strongEmphasis
    case strikethrough
    case highlight
    case code
    case linkText
    case linkURL
    case imageAlt
    case autolink
    case footnoteRef
    case math
    case html
    case escape
    case taskMarker(TaskState)
    case calloutLabel(CalloutKind?)
    case hardBreak
}

struct InlineToken: Equatable {
    var range: NSRange
    var kind: InlineKind
}

/// An image that is the whole content of its line, so it can be rendered rather
/// than written out.
struct BlockImage: Equatable {
    /// The raw destination, still to be resolved against the document's folder.
    var destination: String
    var altRange: NSRange
    /// The whole `![alt](destination)` span.
    var range: NSRange
}

struct ParsedDocument {
    var lines: [MDLine]
    /// Reference link targets, keyed by lowercased label.
    var linkDefinitions: [String: String] = [:]

    /// Index of the line containing `location`, using binary search.
    func lineIndex(at location: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let line = lines[mid]
            if location < line.fullRange.location {
                high = mid - 1
            } else if location >= line.fullRange.location + line.fullRange.length {
                low = mid + 1
            } else {
                return mid
            }
        }
        // A caret sitting at the very end of the document belongs to the last line.
        return lines.count - 1
    }

    /// All line indices intersecting `range`.
    func lineIndices(in range: NSRange) -> Range<Int> {
        guard !lines.isEmpty else { return 0..<0 }
        let start = lineIndex(at: range.location) ?? 0
        let endLocation = max(range.location, NSMaxRange(range) - 1)
        let end = lineIndex(at: endLocation) ?? lines.count - 1
        return start..<min(end + 1, lines.count)
    }
}

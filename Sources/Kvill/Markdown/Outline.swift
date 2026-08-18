import Foundation

/// The headings of a document, in order, for jumping around a long one.
///
/// Pure: a parsed document in, a list out, no view and no text storage. The
/// awkward cases are all here rather than in the sidebar, so they can be checked
/// without building one.
enum Outline {

    /// One heading: how deep, what it says, and where it starts.
    struct Entry: Equatable {
        let level: Int
        let title: String
        /// Where the heading's line begins, for scrolling to it.
        let location: Int
        /// How far to indent it, which is not the same as its level: a document
        /// that starts at `##` should not be indented for a `#` it never has.
        var indent: Int = 0
    }

    /// Every heading in the document.
    ///
    /// The title is the heading's text, not its source, so `## Getting started`
    /// reads as "Getting started" and inline marks come out as their words. A
    /// heading with nothing after the hashes is skipped: it is a marker someone
    /// is in the middle of typing, and a blank row is worse than no row.
    static func entries(of parsed: ParsedDocument, in text: String) -> [Entry] {
        let source = text as NSString
        var found: [Entry] = []

        for line in parsed.lines {
            guard case .heading(let level) = line.kind else { continue }
            // The heading's own text, never the whole line. Falling back to the
            // line put a row reading "##" in the list while someone was still
            // typing the marker.
            let range = line.contentRange
            guard range.length > 0,
                  range.location >= 0, NSMaxRange(range) <= source.length else { continue }
            let title = source.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Trailing hashes are the closed ATX form, and are punctuation
            // rather than part of the title.
            let cleaned = title.replacingOccurrences(
                of: "\\s+#+\\s*$", with: "", options: .regularExpression)
            guard !cleaned.isEmpty else { continue }
            found.append(Entry(level: level, title: cleaned, location: line.range.location))
        }

        return indented(found)
    }

    /// Turns levels into indents.
    ///
    /// Levels are absolute and documents are not: a README that starts at `#`
    /// and one that starts at `##` should look the same in the sidebar. Depth is
    /// counted from the levels the document actually uses, so a jump from `##`
    /// straight to `####` indents by one step and not by two.
    static func indented(_ entries: [Entry]) -> [Entry] {
        var stack: [Int] = []
        return entries.map { entry in
            while let last = stack.last, last >= entry.level { stack.removeLast() }
            let indent = stack.count
            stack.append(entry.level)
            var copy = entry
            copy.indent = indent
            return copy
        }
    }

    /// The entry the caret is inside, so the sidebar can light the section being
    /// worked on. The last heading at or before the caret.
    static func entry(at location: Int, in entries: [Entry]) -> Entry? {
        var current: Entry?
        for entry in entries where entry.location <= location { current = entry }
        return current
    }
}

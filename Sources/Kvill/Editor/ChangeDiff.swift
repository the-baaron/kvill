import Foundation

/// Works out what changed when a file is rewritten underneath the window.
///
/// This exists because something else is editing your files: an agent, a script,
/// a sync client. Kvill already reloads the page when that happens, and until
/// now it did so silently, so a rewritten section arrived with nothing to say
/// which part of the page had moved.
///
/// Pure, and deliberately so. Everything here is two strings in and character
/// ranges out, with no text view, no layout and no clock, which is the only way
/// the awkward cases can be checked at all.
enum ChangeDiff {

    /// How many lines each side of the change may be before the line-by-line
    /// comparison is abandoned.
    ///
    /// The comparison is a table of one side against the other, so its cost is
    /// the product. A whole file replaced end to end is the case that would sit
    /// there multiplying, and it is also the case where the answer does not
    /// matter: everything changed. The budget is on the product rather than on
    /// either side, so a hundred lines against three still gets the precise
    /// answer.
    static let comparisonBudget = 250_000

    /// The ranges of `new` that differ from `old`.
    ///
    /// Ranges are in UTF-16 offsets, which is what `NSRange` and the text view
    /// both speak. An empty result means the two are identical.
    static func changedRanges(from old: String, to new: String) -> [NSRange] {
        if old == new { return [] }
        let oldLines = lines(of: old)
        let newLines = lines(of: new)

        // Matching lines at each end are not part of the change and are the bulk
        // of the file in almost every real edit, so they go first and cheaply.
        var head = 0
        while head < oldLines.count, head < newLines.count,
              oldLines[head].text == newLines[head].text { head += 1 }

        var tail = 0
        while tail < oldLines.count - head, tail < newLines.count - head,
              oldLines[oldLines.count - 1 - tail].text == newLines[newLines.count - 1 - tail].text {
            tail += 1
        }

        let oldMiddle = Array(oldLines[head..<(oldLines.count - tail)])
        let newMiddle = Array(newLines[head..<(newLines.count - tail)])

        // Nothing added, only removed: there is no new text to light up, so mark
        // where it went by pointing at the join.
        if newMiddle.isEmpty {
            guard !oldMiddle.isEmpty, head < newLines.count else { return [] }
            return [NSRange(location: newLines[head].range.location, length: 0)]
        }

        // One line for one line is the common agent edit and the case worth
        // being precise about: narrow to the words that actually differ rather
        // than lighting the whole line.
        if oldMiddle.count == 1, newMiddle.count == 1 {
            return [narrowed(from: oldMiddle[0], to: newMiddle[0])]
        }

        if oldMiddle.count * newMiddle.count > comparisonBudget {
            // Too big to compare line by line, and past this size the honest
            // answer is that the whole middle is new.
            return [span(newMiddle)]
        }

        let kept = commonLines(oldMiddle.map(\.text), newMiddle.map(\.text))
        var changed: [Line] = []
        for (index, line) in newMiddle.enumerated() where !kept.contains(index) {
            changed.append(line)
        }
        return merge(changed)
    }

    // MARK: - Lines

    /// One line of a document, and where it sits in it.
    struct Line {
        let text: String
        let range: NSRange
    }

    /// Splits into lines, keeping each one's range in the original.
    ///
    /// The newline is left out of the range. Including it made a changed line
    /// light up the full width of the page, out past the last character, which
    /// reads as a selection rather than as a mark on the words.
    static func lines(of string: String) -> [Line] {
        let text = string as NSString
        var result: [Line] = []
        var index = 0
        while index <= text.length {
            let rest = NSRange(location: index, length: text.length - index)
            let newline = text.rangeOfCharacter(from: .newlines, options: [], range: rest)
            let end = newline.location == NSNotFound ? text.length : newline.location
            result.append(Line(
                text: text.substring(with: NSRange(location: index, length: end - index)),
                range: NSRange(location: index, length: end - index)))
            if newline.location == NSNotFound { break }
            index = NSMaxRange(newline)
        }
        return result
    }

    /// The change within a single rewritten line, rather than the whole line.
    private static func narrowed(from old: Line, to new: Line) -> NSRange {
        let oldText = Array(old.text.utf16)
        let newText = Array(new.text.utf16)

        var start = 0
        while start < oldText.count, start < newText.count, oldText[start] == newText[start] {
            start += 1
        }
        var back = 0
        while back < oldText.count - start, back < newText.count - start,
              oldText[oldText.count - 1 - back] == newText[newText.count - 1 - back] {
            back += 1
        }

        let length = newText.count - start - back
        // Purely a deletion within the line: nothing new to mark, so the join is
        // marked instead and the caller draws a sliver there.
        return NSRange(location: new.range.location + start, length: max(0, length))
    }

    /// The whole of a run of lines, as one range.
    private static func span(_ lines: [Line]) -> NSRange {
        guard let first = lines.first, let last = lines.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.range.location,
                       length: NSMaxRange(last.range) - first.range.location)
    }

    /// Runs of adjacent changed lines, joined so the highlight is one shape per
    /// block rather than one per line with hairlines between them.
    private static func merge(_ lines: [Line]) -> [NSRange] {
        var result: [NSRange] = []
        var run: [Line] = []
        var previous: Int?
        for line in lines {
            if let previous, line.range.location != previous {
                result.append(span(run))
                run = []
            }
            run.append(line)
            previous = NSMaxRange(line.range) + 1
        }
        if !run.isEmpty { result.append(span(run)) }
        return result
    }

    /// Which lines of `new` also appear, in order, in `old`.
    ///
    /// A longest common subsequence, which is what makes an inserted paragraph
    /// light up as an inserted paragraph rather than shunting every line below
    /// it into the answer as well.
    private static func commonLines(_ old: [String], _ new: [String]) -> Set<Int> {
        let rows = old.count, columns = new.count
        guard rows > 0, columns > 0 else { return [] }

        var table = [Int](repeating: 0, count: (rows + 1) * (columns + 1))
        let width = columns + 1
        for i in stride(from: rows - 1, through: 0, by: -1) {
            for j in stride(from: columns - 1, through: 0, by: -1) {
                table[i * width + j] = old[i] == new[j]
                    ? table[(i + 1) * width + (j + 1)] + 1
                    : max(table[(i + 1) * width + j], table[i * width + (j + 1)])
            }
        }

        var kept = Set<Int>()
        var i = 0, j = 0
        while i < rows, j < columns {
            if old[i] == new[j] {
                kept.insert(j)
                i += 1; j += 1
            } else if table[(i + 1) * width + j] >= table[i * width + (j + 1)] {
                i += 1
            } else {
                j += 1
            }
        }
        return kept
    }
}

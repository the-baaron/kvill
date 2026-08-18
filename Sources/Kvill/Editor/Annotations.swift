import Foundation

/// The parts of annotating that are arithmetic on a string, kept apart from the
/// text view so they can be checked without one.
enum Annotations {

    /// The next free footnote marker.
    ///
    /// Numbered, and numbered from what the document already uses rather than
    /// from how many notes there are: deleting note 2 of three must not hand the
    /// next one a marker that is still in use further up.
    static func nextMarker(in text: String) -> Int {
        var highest = 0
        let source = text as NSString
        let pattern = try? NSRegularExpression(pattern: "\\[\\^(\\d+)\\]")
        pattern?.enumerateMatches(
            in: text, range: NSRange(location: 0, length: source.length)
        ) { match, _, _ in
            guard let match, match.numberOfRanges > 1 else { return }
            let number = Int(source.substring(with: match.range(at: 1))) ?? 0
            highest = max(highest, number)
        }
        return highest + 1
    }

    /// What to put between the end of the document and a new footnote
    /// definition, so notes end up in one block with a blank line above it and
    /// the document does not grow a run of empty lines.
    static func separator(endingIn text: String) -> String {
        if text.isEmpty { return "" }
        // Already sitting under a footnote definition: one newline joins the
        // block rather than opening a second one.
        let trimmed = text.hasSuffix("\n") ? String(text.dropLast()) : text
        if let last = trimmed.split(separator: "\n", omittingEmptySubsequences: false).last,
           last.hasPrefix("[^") {
            return text.hasSuffix("\n") ? "" : "\n"
        }
        if text.hasSuffix("\n\n") { return "" }
        if text.hasSuffix("\n") { return "\n" }
        return "\n\n"
    }
}

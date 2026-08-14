import AppKit

/// The Format menu. Every command is a text edit on the document, routed through
/// `shouldChangeText` so undo groups the way the user expects.
extension EditorViewController {

    // MARK: - Inline wrapping

    @objc func toggleBold(_ sender: Any?) { wrap("**") }
    @objc func toggleItalic(_ sender: Any?) { wrap("_") }
    @objc func toggleStrikethrough(_ sender: Any?) { wrap("~~") }
    @objc func toggleHighlight(_ sender: Any?) { wrap("==") }
    @objc func toggleInlineCode(_ sender: Any?) { wrap("`") }
    @objc func toggleMath(_ sender: Any?) { wrap("$") }

    @objc func insertLink(_ sender: Any?) {
        let text = textView.string as NSString
        var range = selectionOrWord()
        if range.length == 0 {
            replace(range, with: "[](url)")
            textView.setSelectedRange(NSRange(location: range.location + 1, length: 0))
            return
        }
        let label = text.substring(with: range)
        replace(range, with: "[\(label)](url)")
        // Select the placeholder destination so typing replaces it.
        range = NSRange(location: range.location + label.count + 3, length: 3)
        textView.setSelectedRange(range)
    }

    @objc func insertImage(_ sender: Any?) {
        let range = selectionOrWord()
        let text = textView.string as NSString
        let label = range.length > 0 ? text.substring(with: range) : "alt text"
        replace(range, with: "![\(label)](url)")
        textView.setSelectedRange(NSRange(location: range.location + label.count + 4, length: 3))
    }

    @objc func insertFootnote(_ sender: Any?) {
        let caret = textView.selectedRange()
        replace(NSRange(location: caret.location, length: 0), with: "[^1]")
        textView.setSelectedRange(NSRange(location: caret.location + 2, length: 1))
    }

    // MARK: - Headings

    @objc func setHeading1(_ sender: Any?) { setHeading(1) }
    @objc func setHeading2(_ sender: Any?) { setHeading(2) }
    @objc func setHeading3(_ sender: Any?) { setHeading(3) }
    @objc func setHeading4(_ sender: Any?) { setHeading(4) }
    @objc func setHeading5(_ sender: Any?) { setHeading(5) }
    @objc func setHeading6(_ sender: Any?) { setHeading(6) }
    @objc func setBodyText(_ sender: Any?) { setHeading(0) }

    private func setHeading(_ level: Int) {
        transformSelectedLines { line, text in
            var start = line.range.location
            var end = start
            // Strip any existing heading marker and the space after it.
            while end < NSMaxRange(line.range), text.character(at: end) == 32 { end += 1 }
            start = end
            var hashes = 0
            while end < NSMaxRange(line.range), text.character(at: end) == 35, hashes < 6 {
                end += 1
                hashes += 1
            }
            if hashes > 0 {
                while end < NSMaxRange(line.range), text.character(at: end) == 32 { end += 1 }
            } else {
                end = start
            }
            let replacement = level == 0 ? "" : String(repeating: "#", count: level) + " "
            return (NSRange(location: start, length: end - start), replacement)
        }
    }

    // MARK: - Lists and quotes

    @objc func toggleBulletList(_ sender: Any?) { setListMarker("- ") }
    @objc func toggleNumberedList(_ sender: Any?) { setListMarker("1. ") }
    @objc func toggleTaskList(_ sender: Any?) { setListMarker("- [ ] ") }

    private func setListMarker(_ marker: String) {
        transformSelectedLines { line, text in
            let existing = self.leadingMarkerRange(line, text: text)
            let current = text.substring(with: existing)
            // Applying the same marker twice removes it.
            let replacement = current == marker ? "" : marker
            return (existing, replacement)
        }
    }

    @objc func toggleBlockquote(_ sender: Any?) {
        transformSelectedLines { line, text in
            if line.quoteDepth > 0 {
                var end = line.range.location
                while end < NSMaxRange(line.range), text.character(at: end) == 32 { end += 1 }
                guard end < NSMaxRange(line.range), text.character(at: end) == 62 else { return nil }
                end += 1
                if end < NSMaxRange(line.range), text.character(at: end) == 32 { end += 1 }
                return (NSRange(location: line.range.location, length: end - line.range.location), "")
            }
            return (NSRange(location: line.range.location, length: 0), "> ")
        }
    }

    // MARK: - Blocks

    @objc func insertCodeBlock(_ sender: Any?) {
        let range = textView.selectedRange()
        let text = textView.string as NSString
        let body = range.length > 0 ? text.substring(with: range) : ""
        let block = "```\n\(body)\n```"
        replace(range, with: block)
        // Put the caret on the info string so a language can be typed straight away.
        textView.setSelectedRange(NSRange(location: range.location + 3, length: 0))
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        let caret = textView.selectedRange()
        let prefix = needsLeadingNewline(at: caret.location) ? "\n" : ""
        replace(caret, with: "\(prefix)---\n")
        textView.setSelectedRange(
            NSRange(location: caret.location + prefix.count + 4, length: 0))
    }

    @objc func insertTable(_ sender: Any?) {
        let caret = textView.selectedRange()
        let prefix = needsLeadingNewline(at: caret.location) ? "\n" : ""
        let table = """
        \(prefix)| Column | Column |
        | --- | --- |
        |  |  |

        """
        replace(caret, with: table)
        textView.setSelectedRange(NSRange(location: caret.location + prefix.count + 2, length: 6))
    }

    @objc func insertCalloutNote(_ sender: Any?) { insertCallout(.note) }
    @objc func insertCalloutTip(_ sender: Any?) { insertCallout(.tip) }
    @objc func insertCalloutImportant(_ sender: Any?) { insertCallout(.important) }
    @objc func insertCalloutWarning(_ sender: Any?) { insertCallout(.warning) }
    @objc func insertCalloutCaution(_ sender: Any?) { insertCallout(.caution) }

    private func insertCallout(_ kind: CalloutKind) {
        let range = textView.selectedRange()
        let text = textView.string as NSString
        let body = range.length > 0 ? text.substring(with: range) : ""
        let quoted = body.isEmpty
            ? ""
            : body.components(separatedBy: "\n").map { "> \($0)" }.joined(separator: "\n")
        let prefix = needsLeadingNewline(at: range.location) ? "\n" : ""
        let block = quoted.isEmpty
            ? "\(prefix)> [!\(kind.rawValue)]\n> "
            : "\(prefix)> [!\(kind.rawValue)]\n\(quoted)"
        replace(range, with: block)
        textView.setSelectedRange(
            NSRange(location: range.location + (block as NSString).length, length: 0))
    }

    // MARK: - Shared helpers

    /// Wraps the selection (or the word under the caret) in `delimiter`, or
    /// removes the delimiter if it is already there.
    private func wrap(_ delimiter: String) {
        let text = textView.string as NSString
        let range = selectionOrWord()
        let length = (delimiter as NSString).length

        // Already wrapped? Unwrap.
        let outerStart = range.location - length
        let outerEnd = NSMaxRange(range) + length
        if outerStart >= 0, outerEnd <= text.length,
           text.substring(with: NSRange(location: outerStart, length: length)) == delimiter,
           text.substring(with: NSRange(location: NSMaxRange(range), length: length)) == delimiter {
            let body = text.substring(with: range)
            replace(NSRange(location: outerStart, length: outerEnd - outerStart), with: body)
            textView.setSelectedRange(NSRange(location: outerStart, length: range.length))
            return
        }

        let body = range.length > 0 ? text.substring(with: range) : ""
        replace(range, with: delimiter + body + delimiter)
        if body.isEmpty {
            textView.setSelectedRange(NSRange(location: range.location + length, length: 0))
        } else {
            textView.setSelectedRange(NSRange(location: range.location + length, length: range.length))
        }
    }

    /// The current selection, or the word the caret sits inside.
    private func selectionOrWord() -> NSRange {
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return selection }

        let text = textView.string as NSString
        guard text.length > 0 else { return selection }

        var start = selection.location
        var end = selection.location
        while start > 0, isWordCharacter(text.character(at: start - 1)) { start -= 1 }
        while end < text.length, isWordCharacter(text.character(at: end)) { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    private func isWordCharacter(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            || c == 95 || c == 45 || c > 127
    }

    /// The leading list marker plus trailing space, or an empty range at the
    /// line's first non-space character.
    private func leadingMarkerRange(_ line: MDLine, text: NSString) -> NSRange {
        guard case .listItem = line.kind else {
            var start = line.range.location
            while start < NSMaxRange(line.range), text.character(at: start) == 32 { start += 1 }
            return NSRange(location: start, length: 0)
        }
        let start = line.markerRange.location
        var end = NSMaxRange(line.markerRange)
        while end < NSMaxRange(line.range), text.character(at: end) == 32 { end += 1 }
        // A task item's `[ ]` is part of the marker for toggling purposes.
        if end + 2 < NSMaxRange(line.range), text.character(at: end) == 91 {
            let close = end + 2
            if text.character(at: close) == 93 {
                end = close + 1
                while end < NSMaxRange(line.range), text.character(at: end) == 32 { end += 1 }
            }
        }
        return NSRange(location: start, length: end - start)
    }

    /// Applies an edit to every line touched by the selection, working backwards
    /// so earlier ranges stay valid.
    private func transformSelectedLines(
        _ transform: (MDLine, NSString) -> (NSRange, String)?
    ) {
        let selection = textView.selectedRange()
        let indices = parsed.lineIndices(in: selection)
        guard !indices.isEmpty, let storage = textView.textStorage else { return }

        let text = textView.string as NSString
        var edits: [(NSRange, String)] = []
        for index in indices {
            if let edit = transform(parsed.lines[index], text) { edits.append(edit) }
        }
        guard !edits.isEmpty else { return }

        textView.undoManager?.beginUndoGrouping()
        for (range, replacement) in edits.reversed() {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else { continue }
            storage.replaceCharacters(in: range, with: replacement)
            textView.didChangeText()
        }
        textView.undoManager?.endUndoGrouping()
    }

    private func replace(_ range: NSRange, with string: String) {
        guard let storage = textView.textStorage,
              textView.shouldChangeText(in: range, replacementString: string) else { return }
        storage.replaceCharacters(in: range, with: string)
        textView.didChangeText()
    }

    /// True when a block insert at `location` would run into existing text.
    private func needsLeadingNewline(at location: Int) -> Bool {
        guard location > 0 else { return false }
        let text = textView.string as NSString
        return text.character(at: location - 1) != 10
    }
}

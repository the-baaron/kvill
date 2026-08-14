import Foundation

/// Pads the cells of a Markdown table with spaces so the columns line up in the
/// file itself.
///
/// This is what makes tables readable without any custom layout. The document is
/// set in a monospace face, so once the source is padded the columns align by
/// construction: nothing is measured, nothing is kerned, and the file stays
/// tidy everywhere else it is read, including a diff and GitHub.
///
///     | Feature | Shortcut | Notes |            | Feature    | Shortcut | Notes    |
///     | --- | --- | --- |               ->      | ---------- | -------- | -------- |
///     | Bold | Cmd B | Wraps a word |           | Bold       | Cmd B    | Wraps... |
///
/// Cell width is counted in characters. That is exact for the Latin text a
/// table normally holds; a cell of double-width CJK glyphs will pad short.
enum TableFormatter {

    enum Alignment {
        case none, left, center, right
    }

    /// One line to rewrite. Ranges are the line's characters, not including the
    /// newline, so applying them never disturbs the file's line endings.
    struct Edit {
        var range: NSRange
        var text: String
    }

    // MARK: - Whole document

    /// Every table in the text, padded. Nil when nothing needed changing.
    static func normalized(_ text: String) -> String? {
        let string = text as NSString
        let document = MarkdownParser.parse(string)
        let edits = allEdits(in: document, text: string)
        guard !edits.isEmpty else { return nil }

        let output = NSMutableString(string: text)
        // Back to front, so an earlier edit's range is still valid.
        for edit in edits.reversed() {
            output.replaceCharacters(in: edit.range, with: edit.text)
        }
        return output as String
    }

    static func allEdits(in document: ParsedDocument, text: NSString) -> [Edit] {
        var result: [Edit] = []
        var index = 0
        while index < document.lines.count {
            guard document.lines[index].kind.isTable else {
                index += 1
                continue
            }
            let end = tableEnd(from: index, in: document)
            result += edits(forTableFrom: index, to: end, in: document, text: text)
            index = end
        }
        return result
    }

    // MARK: - One table

    /// The table the given line belongs to, padded. Empty when it is already
    /// laid out, or when the line is not in a table.
    static func edits(forLine line: Int, in document: ParsedDocument, text: NSString) -> [Edit] {
        guard line >= 0, line < document.lines.count, document.lines[line].kind.isTable else {
            return []
        }
        var start = line
        while start > 0, document.lines[start - 1].kind.isTable { start -= 1 }
        return edits(forTableFrom: start, to: tableEnd(from: start, in: document),
                     in: document, text: text)
    }

    private static func tableEnd(from start: Int, in document: ParsedDocument) -> Int {
        var end = start
        while end < document.lines.count, document.lines[end].kind.isTable { end += 1 }
        return end
    }

    private static func edits(
        forTableFrom start: Int, to end: Int, in document: ParsedDocument, text: NSString
    ) -> [Edit] {
        let lines = Array(document.lines[start..<end])
        guard lines.count >= 2 else { return [] }

        let rows = lines.map { text.substring(with: $0.range) }
        let cells = rows.map(self.cells)

        // The delimiter row is the second line of a table, always.
        let alignments = self.alignments(cells[1])
        let columns = max(alignments.count, cells.map(\.count).max() ?? 0)
        guard columns > 0 else { return [] }

        var widths = [Int](repeating: 3, count: columns)
        for (index, row) in cells.enumerated() where index != 1 {
            for (column, cell) in row.enumerated() where column < columns {
                widths[column] = max(widths[column], cell.count)
            }
        }

        var result: [Edit] = []
        for (offset, line) in lines.enumerated() {
            let rebuilt = offset == 1
                ? delimiterRow(widths: widths, alignments: alignments)
                : row(cells[offset], widths: widths, alignments: alignments)
            guard rebuilt != rows[offset] else { continue }
            result.append(Edit(range: line.range, text: rebuilt))
        }
        return result
    }

    // MARK: - Reading a table out

    /// A table lifted out of the document, ready to be edited as data.
    struct Table {
        /// Characters from the start of the first row to the end of the last,
        /// with no trailing newline, so it can be replaced wholesale.
        var range: NSRange
        /// The header first, then the body. The delimiter row is not here: it
        /// carries alignment, which is held separately, and nothing else.
        var rows: [[String]]
        var alignments: [Alignment]

        var columnCount: Int { max(alignments.count, rows.map(\.count).max() ?? 0) }
    }

    /// The table containing the given line, or nil when there is not one.
    static func table(atLine line: Int, in document: ParsedDocument, text: NSString) -> Table? {
        guard line >= 0, line < document.lines.count, document.lines[line].kind.isTable else {
            return nil
        }
        var start = line
        while start > 0, document.lines[start - 1].kind.isTable { start -= 1 }
        let end = tableEnd(from: start, in: document)
        guard end - start >= 2 else { return nil }

        let lines = Array(document.lines[start..<end])
        let parsedRows = lines.map { cells(text.substring(with: $0.range)) }
        let alignments = self.alignments(parsedRows[1])

        var rows = parsedRows
        rows.remove(at: 1)

        let first = lines[0].range
        let last = lines[lines.count - 1].range
        return Table(
            range: NSRange(location: first.location, length: NSMaxRange(last) - first.location),
            rows: rows,
            alignments: alignments)
    }

    /// The Markdown for a table held as data. `rows[0]` is the header; the
    /// delimiter row is written for you.
    static func render(rows: [[String]], alignments: [Alignment]) -> String {
        guard let header = rows.first else { return "" }
        let columns = max(alignments.count, rows.map(\.count).max() ?? 0)
        guard columns > 0 else { return "" }

        var widths = [Int](repeating: 3, count: columns)
        for row in rows {
            for (column, cell) in row.enumerated() where column < columns {
                widths[column] = max(widths[column], cell.count)
            }
        }

        var lines = [row(header, widths: widths, alignments: alignments)]
        lines.append(delimiterRow(widths: widths, alignments: alignments))
        for body in rows.dropFirst() {
            lines.append(row(body, widths: widths, alignments: alignments))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Cells

    /// Splits a row on its unescaped pipes, dropping the empty fields that a
    /// leading or trailing pipe produces, and trims each cell.
    static func cells(_ row: String) -> [String] {
        let trimmed = row.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }

        var fields: [String] = []
        var current = ""
        var escaped = false
        for character in trimmed {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if character == "|" {
                fields.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        fields.append(current)

        // A leading `|` opens an empty field before the first cell, and a
        // trailing one closes an empty field after the last. Those are the
        // table's edges, not columns. Testing the pipes rather than the fields
        // keeps a genuinely empty first or last cell.
        if trimmed.hasPrefix("|"), !fields.isEmpty { fields.removeFirst() }
        if trimmed.hasSuffix("|"), fields.count > 1 { fields.removeLast() }

        return fields.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func alignments(_ delimiterCells: [String]) -> [Alignment] {
        delimiterCells.map { cell in
            let left = cell.hasPrefix(":")
            let right = cell.hasSuffix(":")
            switch (left, right) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            case (false, false): return .none
            }
        }
    }

    // MARK: - Rebuilding

    private static func row(
        _ cells: [String], widths: [Int], alignments: [Alignment]
    ) -> String {
        var parts: [String] = []
        parts.reserveCapacity(widths.count)
        for column in widths.indices {
            let cell = column < cells.count ? cells[column] : ""
            let alignment = column < alignments.count ? alignments[column] : .none
            parts.append(pad(cell, to: widths[column], alignment: alignment))
        }
        return "| " + parts.joined(separator: " | ") + " |"
    }

    private static func delimiterRow(widths: [Int], alignments: [Alignment]) -> String {
        var parts: [String] = []
        parts.reserveCapacity(widths.count)
        for column in widths.indices {
            let width = widths[column]
            let alignment = column < alignments.count ? alignments[column] : .none
            switch alignment {
            case .none:
                parts.append(String(repeating: "-", count: width))
            case .left:
                parts.append(":" + String(repeating: "-", count: width - 1))
            case .right:
                parts.append(String(repeating: "-", count: width - 1) + ":")
            case .center:
                parts.append(":" + String(repeating: "-", count: width - 2) + ":")
            }
        }
        return "| " + parts.joined(separator: " | ") + " |"
    }

    private static func pad(_ cell: String, to width: Int, alignment: Alignment) -> String {
        let short = width - cell.count
        guard short > 0 else { return cell }
        switch alignment {
        case .right:
            return String(repeating: " ", count: short) + cell
        case .center:
            let left = short / 2
            return String(repeating: " ", count: left) + cell
                + String(repeating: " ", count: short - left)
        case .none, .left:
            return cell + String(repeating: " ", count: short)
        }
    }
}

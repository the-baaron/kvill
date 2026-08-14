import Foundation

/// Rewrites setext headings as ATX ones when a document is opened.
///
///     Title          becomes    # Title
///     =====
///
/// Setext headings are awkward in a live editor for two reasons: the underline
/// is a second line that has to be kept in step with the first, and `---` typed
/// under a paragraph silently turns it into a heading when a horizontal rule was
/// meant. Normalising on open removes both, and the parser then treats `---` as
/// nothing but a rule.
///
/// This only ever rewrites headings. Front matter, fenced code and anything that
/// is already a list, quote or table are left exactly as they were.
enum SetextNormalizer {

    /// The converted text, or nil when there was nothing to convert.
    static func normalized(_ text: String) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return nil }

        var output: [String] = []
        output.reserveCapacity(lines.count)
        var changed = false
        var index = 0

        // YAML front matter is a block of `key: value` lines closed by `---`.
        // Without skipping it, that closing line reads as a setext underline and
        // the last key would be turned into a heading.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            output.append(lines[0])
            index = 1
            while index < lines.count {
                let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                output.append(lines[index])
                index += 1
                if trimmed == "---" || trimmed == "..." { break }
            }
        }

        var fence: String?

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
                output.append(line)
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                output.append(line)
                index += 1
                continue
            }

            if index + 1 < lines.count,
               let level = underlineLevel(lines[index + 1]),
               canBecomeHeading(trimmed) {
                output.append(String(repeating: "#", count: level) + " " + trimmed)
                changed = true
                index += 2
                continue
            }

            output.append(line)
            index += 1
        }

        guard changed else { return nil }
        lines = output
        return lines.joined(separator: "\n")
    }

    /// 1 for `===`, 2 for `---`, nil for anything else.
    private static func underlineLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.allSatisfy({ $0 == "=" }) { return 1 }
        // Two dashes is the shortest that reads as an underline rather than a
        // stray character.
        if trimmed.count >= 2, trimmed.allSatisfy({ $0 == "-" }) { return 2 }
        return nil
    }

    /// True when a line is ordinary prose, so an underline under it really was
    /// meant as a heading.
    private static func canBecomeHeading(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        guard let first = trimmed.first else { return false }

        // Already structural: heading, quote, list, table, rule, definition, HTML.
        if "#>|<".contains(first) { return false }
        if first == "-" || first == "*" || first == "+" || first == "=" { return false }
        if first == "[" { return false }
        if first == ":" { return false }
        if first.isNumber, trimmed.dropFirst().first == "." { return false }
        // An indented line is code or a nested block, not a title.
        return true
    }
}

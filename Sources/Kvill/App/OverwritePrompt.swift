import AppKit

/// Asks before writing over a file something else has changed, and shows what
/// would be lost if asked.
///
/// Only reachable out of live mode. In live mode the page already holds whatever
/// the file holds, so there is never anything unseen to write over. Out of it
/// the window deliberately ignores the file until told otherwise, which is the
/// setting working as intended right up to the moment you press save.
///
/// "Are you sure" is not a question anyone can answer on its own, so the answer
/// is one button away.
extension MarkdownDocument {

    func askBeforeOverwriting(_ decide: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(displayName ?? "This file") changed while you had it open."
        alert.informativeText =
            "Something else wrote to this file after you opened it. Saving now replaces "
            + "what it wrote with what is in this window."
        alert.addButton(withTitle: "Save Anyway")
        alert.addButton(withTitle: "View Changes…")
        alert.addButton(withTitle: "Cancel")

        // Cancel on Escape, and no default button doing something irreversible
        // on a stray Return.
        alert.buttons[0].keyEquivalent = ""
        alert.buttons[2].keyEquivalent = "\u{1b}"

        guard let window = windowControllers.first?.window else {
            decide(alert.runModal() == .alertFirstButtonReturn)
            return
        }

        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                decide(true)
            case .alertSecondButtonReturn:
                // Back to the same question once it has been looked at, because
                // showing the changes is not itself an answer.
                self?.showChanges { self?.askBeforeOverwriting(decide) }
            default:
                decide(false)
            }
        }
    }

    /// Shows what the file holds now against what this window would write.
    func showChanges(_ done: @escaping () -> Void) {
        guard let window = windowControllers.first?.window else { return done() }
        let mine = controller?.text ?? ""
        let theirs = diskText ?? mine
        let sheet = ChangesSheet(theirs: theirs, mine: mine, name: displayName ?? "this file")
        sheet.present(over: window, then: done)
    }
}

/// A plain listing of what differs, in a sheet.
///
/// Deliberately the ordinary shape: a scrolling text view in a panel with one
/// button. Two columns side by side were tried on paper and need a window twice
/// the width to say the same thing, and this has to open over a document window
/// of whatever size someone happens to have.
final class ChangesSheet: NSObject {

    private let theirs: String
    private let mine: String
    private let name: String
    private var panel: NSWindow?
    private var done: (() -> Void)?

    init(theirs: String, mine: String, name: String) {
        self.theirs = theirs
        self.mine = mine
        self.name = name
    }

    func present(over window: NSWindow, then done: @escaping () -> Void) {
        self.done = done

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "Changes to \(name)"

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 16, height: 14)
        text.textStorage?.setAttributedString(Self.listing(theirs: theirs, mine: mine))
        scroll.documentView = text

        let explain = NSTextField(labelWithString:
            "On disk, written by something else, against what this window would save.")
        explain.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        explain.textColor = .secondaryLabelColor
        explain.translatesAutoresizingMaskIntoConstraints = false

        let close = NSButton(title: "Done", target: self, action: #selector(dismiss))
        close.keyEquivalent = "\r"
        close.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(explain)
        content.addSubview(close)
        NSLayoutConstraint.activate([
            explain.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            explain.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            explain.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),

            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: explain.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),

            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        panel.contentView = content
        self.panel = panel

        window.beginSheet(panel) { [weak self] _ in
            let finish = self?.done
            self?.done = nil
            self?.panel = nil
            finish?()
        }
    }

    @objc private func dismiss() {
        guard let panel, let parent = panel.sheetParent else { return }
        parent.endSheet(panel)
    }

    /// The listing itself: changed lines, with what is on disk against what this
    /// window holds. Built from the same diff that lights up the page, so the
    /// two can never disagree about what counts as a change.
    static func listing(theirs: String, mine: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let mono = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)

        func append(_ line: String, _ color: NSColor) {
            result.append(NSAttributedString(
                string: line + "\n",
                attributes: [.font: mono, .foregroundColor: color]))
        }

        let theirLines = ChangeDiff.lines(of: theirs).map(\.text)
        let myLines = ChangeDiff.lines(of: mine).map(\.text)

        // Both directions, so a line only this window has shows up as well as a
        // line only the file has. One direction alone reads as though nothing
        // would be lost, which is the opposite of what this sheet is for.
        let onlyOnDisk = ChangeDiff.changedRanges(from: mine, to: theirs)
        let onlyHere = ChangeDiff.changedRanges(from: theirs, to: mine)

        if onlyOnDisk.isEmpty && onlyHere.isEmpty {
            append("The two are identical.", .secondaryLabelColor)
            return result
        }

        append("On disk now", .secondaryLabelColor)
        for text in Self.texts(of: onlyOnDisk, in: theirs, whenEmpty: theirLines) {
            append("  " + text, .systemGreen)
        }
        append("", .labelColor)
        append("In this window, and what would be written", .secondaryLabelColor)
        for text in Self.texts(of: onlyHere, in: mine, whenEmpty: myLines) {
            append("  " + text, .systemRed)
        }
        return result
    }

    /// The whole lines a set of changes touches.
    ///
    /// Widened to line boundaries on purpose. The diff narrows a reworded line
    /// to the words that differ, which is right for marking the page and wrong
    /// here: "their new" on its own is not something anyone can weigh against
    /// "my own", and this sheet exists to be weighed.
    private static func texts(
        of ranges: [NSRange], in string: String, whenEmpty: [String]
    ) -> [String] {
        guard !ranges.isEmpty else { return ["(nothing)"] }
        let text = string as NSString
        var lines: [String] = []
        var taken = Set<Int>()
        for range in ranges {
            guard range.location <= text.length else { continue }
            if range.length == 0 {
                lines.append("(text removed here)")
                continue
            }
            let safe = NSRange(location: range.location,
                               length: min(range.length, text.length - range.location))
            let whole = text.lineRange(for: safe)
            // Keyed by where the block starts, so two changes on one line do not
            // list that line twice.
            guard !taken.contains(whole.location) else { continue }
            taken.insert(whole.location)
            let covered = text.substring(with: whole)
                .trimmingCharacters(in: .newlines)
            lines.append(contentsOf: covered.components(separatedBy: "\n"))
        }
        return lines.isEmpty ? ["(nothing)"] : lines
    }
}

import AppKit

/// The About window: what the app is on the left, what just changed on the right.
///
/// AppKit's standard panel was here first and is a single column by design, with
/// no room for release notes beside the name. What it does well is copied rather
/// than reinvented: the same icon, the same centred name and version, the same
/// semantic colours so it reads in both appearances, and ordinary AppKit views
/// throughout.
final class AboutPanel: NSObject, NSWindowDelegate {

    static let shared = AboutPanel()
    static let siteURL = URL(string: "https://baars.design/")!

    /// Why the app is called what it is.
    ///
    /// Short on purpose. The longer version explained the Norwegian spelling of
    /// qu, which is the etymology of the joke rather than the joke.
    static let nameStory = "Quill, but made in Norway."

    private var window: NSWindow?

    static func show(_ sender: Any?) { shared.present() }

    func present() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 400),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.contentView = Self.makeContent()
        panel.center()
        panel.delegate = self
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Let go of it when it closes, so the next About builds a fresh one and
    /// picks up a version or a note that changed underneath it.
    func windowWillClose(_ notification: Notification) { window = nil }

    // MARK: - The two columns

    /// The two columns, built without a window around them, so the checks can
    /// interrogate the real view tree rather than a description of it.
    static func makeContent() -> NSView {
        let content = NSView()

        let identity = makeIdentityColumn()
        let notes = makeNotesColumn()
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        for view in [identity, notes, divider] { content.addSubview(view) }

        NSLayoutConstraint.activate([
            identity.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            // Centred against the notes rather than hung from the top. The notes
            // are as long as they are and the identity never changes height, so
            // aligning both to the top left the short column sitting in a pool
            // of empty space.
            identity.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            identity.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: 32),
            identity.widthAnchor.constraint(equalToConstant: 250),

            divider.leadingAnchor.constraint(equalTo: identity.trailingAnchor, constant: 30),
            divider.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
            divider.widthAnchor.constraint(equalToConstant: 1),

            notes.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 30),
            notes.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            notes.topAnchor.constraint(equalTo: content.topAnchor, constant: 40),
            notes.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28),
        ])
        return content
    }

    private static func makeIdentityColumn() -> NSView {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 84).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 84).isActive = true

        let name = NSTextField(labelWithString: "Kvill")
        name.font = .systemFont(ofSize: 24, weight: .semibold)
        name.alignment = .center

        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        let version = NSTextField(labelWithString: "Version \(short) (\(build))")
        version.font = .systemFont(ofSize: 11)
        version.textColor = .secondaryLabelColor
        version.alignment = .center

        let story = NSTextField(wrappingLabelWithString: nameStory)
        story.font = .systemFont(ofSize: 11.5)
        story.textColor = .secondaryLabelColor
        story.alignment = .center
        story.isSelectable = false

        // A text view rather than a label, because a label with a link attribute
        // draws a link and behaves like text: the pointer stayed an I-beam over
        // it. NSTextView is the component that actually knows what a link is, so
        // the pointer becomes a hand and the click opens the browser without
        // this window knowing anything about URLs.
        let made = NSTextView()
        made.isEditable = false
        made.isSelectable = true
        made.drawsBackground = false
        made.textContainerInset = .zero
        made.textContainer?.lineFragmentPadding = 0
        made.textContainer?.widthTracksTextView = true
        made.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        made.textStorage?.setAttributedString(madeWithLove())
        made.alignment = .center
        made.translatesAutoresizingMaskIntoConstraints = false
        made.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let column = NSStackView(views: [icon, name, version, story, made])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
        column.setCustomSpacing(14, after: icon)
        column.setCustomSpacing(2, after: name)
        column.setCustomSpacing(18, after: version)
        column.setCustomSpacing(16, after: story)
        column.translatesAutoresizingMaskIntoConstraints = false
        story.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        made.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    static func madeWithLove() -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11.5)
        let line = NSMutableAttributedString(
            string: "Made with love by ",
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor])
        line.append(NSAttributedString(
            string: "baars.design",
            attributes: [.font: font, .link: siteURL]))
        return line
    }

    private static func makeNotesColumn() -> NSView {
        let heading = NSTextField(labelWithString: "What's new")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        // A scroll view adds insets of its own accord, which is what pushed the
        // notes two points right of the heading above them. The file tree had
        // the same argument with it.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero

        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 2)
        // A text container pads its line fragments by five points unless told
        // otherwise, and a label does not. That is the whole reason the heading
        // sat five points to the left of the notes under it.
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.textStorage?.setAttributedString(notes())
        scroll.documentView = text
        // Laying out a text view inside a scroll view can leave it showing the
        // end, and it did: the About window opened on the oldest note in the
        // file. Put back to the top once the layout has settled.
        DispatchQueue.main.async {
            text.scrollRangeToVisible(NSRange(location: 0, length: 0))
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        let column = NSStackView(views: [heading, scroll])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 10
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    /// The notes as they ship, set for reading.
    ///
    /// A list of what was added and when, not a list of version numbers: a
    /// version number says nothing to someone who was not watching the version
    /// numbers. Each entry is a name, the day it arrived, and two lines at most.
    ///
    /// Deliberately not the Markdown parser the editor uses. This is a name in
    /// bold and a couple of lines under it, and pulling the whole document
    /// pipeline into a window nobody looks at twice would tie it to the part of
    /// the app that has to stay fast.
    static func notes() -> NSAttributedString {
        let result = NSMutableAttributedString()

        let titleStyle = NSMutableParagraphStyle()
        titleStyle.paragraphSpacingBefore = 16
        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = 2
        bodyStyle.paragraphSpacing = 2

        var first = true
        for entry in raw().components(separatedBy: "\n\n") {
            var lines = entry.split(separator: "\n", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let title = lines.first, title.hasPrefix("**") else { continue }
            lines.removeFirst()

            let heading = NSMutableParagraphStyle()
            heading.setParagraphStyle(titleStyle)
            // No gap above the first one, or the list starts hanging.
            if first { heading.paragraphSpacingBefore = 0 }
            first = false

            result.append(attributedTitle(title, style: heading))
            // Two lines is the limit the entries are written to. Anything past
            // it is a note that outgrew this window and belongs elsewhere.
            let body = lines.prefix(2).joined(separator: " ")
            guard !body.isEmpty else { continue }
            result.append(NSAttributedString(
                string: body + "\n",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: bodyStyle,
                ]))
        }
        return result
    }

    /// A `**Name** - date` line, with the name carrying the weight.
    private static func attributedTitle(
        _ line: String, style: NSParagraphStyle
    ) -> NSAttributedString {
        let stripped = line.replacingOccurrences(of: "**", with: "")
        let parts = stripped.components(separatedBy: " - ")
        let name = parts.first ?? stripped
        let date = parts.count > 1 ? parts.dropFirst().joined(separator: " - ") : nil

        let title = NSMutableAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ])
        if let date {
            title.append(NSAttributedString(
                string: "  " + date,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 10.5),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: style,
                ]))
        }
        title.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: style]))
        return title
    }

    /// The notes file that ships in the bundle.
    ///
    /// Missing is not a crash and not an empty panel: something is said either
    /// way, because an About window that is blank down one side reads as broken
    /// rather than as a build that forgot a file.
    static func raw() -> String {
        guard let url = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return "**What's new** - \n\nThe notes for this build are not in it." }
        return text
    }
}

import AppKit

/// Runtime checks for the parts of the interface a screenshot cannot show.
///
///     Quill --selftest [document.md]
///
/// The floating chrome is built from glass and visual-effect views, which never
/// render in an off-screen window, so the only honest way to know whether they
/// are wired up is to build the real view tree, lay it out, and interrogate it.
enum SelfTest {

    static func run(document: String?) -> Int32 {
        var failures = 0

        // Straight to stderr: buffered stdout is lost if a check crashes, which
        // hides the very line that would say where.
        func say(_ line: String) {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "ok  " : "FAIL"
            if !passed { failures += 1 }
            say("\(mark) \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        }

        // --- Tables ---------------------------------------------------------
        checkTables(check)

        // --- Palettes -------------------------------------------------------
        let ids = Palettes.all.map(\.id)
        check("palettes registered", ids.count == 8, ids.joined(separator: ", "))
        check("glass palettes present",
              ids.contains("frost") && ids.contains("onyx"))
        check("glass palettes are translucent",
              Palettes.theme(id: "frost")?.isTranslucent == true
                && Palettes.theme(id: "onyx")?.isTranslucent == true)

        // --- The real view tree ---------------------------------------------
        let controller = DocumentViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 900, height: 600))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)

        let text = document.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) }
            ?? String(repeating: "A line of the document.\n\n", count: 200)
        controller.loadText(text)
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        controller.view.layoutSubtreeIfNeeded()

        // --- Padding a table on the way out ----------------------------------
        do {
            let editor = controller.editor
            controller.loadText("""
            Before.

            | A | Long heading |
            | --- | --- |
            | 1 | 2 |

            After.
            """)
            controller.view.layoutSubtreeIfNeeded()

            // Caret into the table, then out of it again.
            let inTable = (editor.text as NSString).range(of: "| 1 | 2 |").location + 2
            editor.textView.setSelectedRange(NSRange(location: inTable, length: 0))
            let end = (editor.text as NSString).range(of: "After.").location
            editor.textView.setSelectedRange(NSRange(location: end, length: 0))

            let rows = editor.text.components(separatedBy: "\n")
                .filter { $0.hasPrefix("|") }
            check("table: padded when the caret leaves",
                  rows.count == 3 && Set(rows.map(\.count)).count == 1,
                  rows.map(\.count).description)
            check("table: text around it is untouched",
                  editor.text.hasPrefix("Before.") && editor.text.hasSuffix("After."), "")
        }

        // --- A wide table is fitted to the column -----------------------------
        do {
            let editor = controller.editor
            controller.loadText("""
            Prose that should still wrap where it always did, whatever is below it.

            | a | b |
            | --- | --- |
            | \(String(repeating: "wide ", count: 30)) | x |
            """)
            controller.view.layoutSubtreeIfNeeded()

            let widest = editor.parsed.lines.filter { $0.kind.isTable }.map(\.tableWidth).max() ?? 0
            check("wide table: its width was measured", widest > 100, "\(widest) characters")

            // Nothing about the page changes because a table is wide: no second
            // scroll direction, no container games.
            check("wide table: the page never scrolls sideways",
                  !editor.scrollView.hasHorizontalScroller, "")
            let measure = ThemeManager.shared.theme.metrics.contentWidth
            let container = editor.textView.textContainer?.size.width ?? 0
            check("wide table: the container stays the width of the column",
                  abs(container - measure) < 60,
                  "container \(Int(container)) vs measure \(Int(measure))")

            // It is set smaller so that it fits instead.
            let rows = editor.parsed.lines.filter { $0.kind.isTable }
            let sizes = rows.compactMap { row -> CGFloat? in
                editor.textView.textStorage?
                    .attribute(.font, at: row.range.location, effectiveRange: nil)
                    .flatMap { ($0 as? NSFont)?.pointSize }
            }
            let normal = ThemeManager.shared.theme.monoSmall.pointSize
            check("wide table: it is set smaller to fit",
                  (sizes.max() ?? normal) < normal,
                  "\(sizes.map { Int($0 * 10) }) vs \(Int(normal * 10)) (tenths)")
        }

        // --- Slash menu -------------------------------------------------------
        do {
            check("slash menu: lists every block",
                  SlashCommand.all.count >= 15, "\(SlashCommand.all.count) commands")
            check("slash menu: filters by title",
                  SlashCommand.matching("tab").first?.title == "Table",
                  SlashCommand.matching("tab").first?.title ?? "nothing")
            check("slash menu: filters by keyword",
                  SlashCommand.matching("h1").first?.title == "Heading 1",
                  SlashCommand.matching("h1").first?.title ?? "nothing")
            check("slash menu: nothing matches nonsense",
                  SlashCommand.matching("zzzz").isEmpty, "")

            let panel = SlashMenuPanel()
            check("slash menu: builds", panel.update(query: ""), "")
            check("slash menu: never takes the keyboard", !panel.canBecomeKey, "")
            // A content view with autoresizing turned off gets no size, and the
            // panel comes up empty. This is the check that catches that.
            panel.orderFront(nil)
            let content = panel.contentView
            check("slash menu: the panel has a size",
                  (content?.frame.width ?? 0) > 100 && (content?.frame.height ?? 0) > 40,
                  "\(Int(content?.frame.width ?? 0))x\(Int(content?.frame.height ?? 0))")
            check("slash menu: its list is on screen",
                  content?.subviews.first?.frame.width ?? 0 > 100,
                  "\(Int(content?.subviews.first?.frame.width ?? 0))pt")
            panel.orderOut(nil)

            // Typing `/` in the document opens it.
            controller.loadText("Text\n\n")
            controller.view.layoutSubtreeIfNeeded()
            let editor = controller.editor
            editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
            editor.textView.insertText("/", replacementRange: NSRange(location: 5, length: 0))
            controller.view.layoutSubtreeIfNeeded()
            // Showing it waits a turn of the run loop, so that layout is legal.
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            check("slash menu: a typed slash opens it", editor.isSlashMenuOpen, "")
            editor.closeSlashMenuForTest()

            // A slash inside a word is just a slash.
            controller.loadText("http:/\n")
            editor.textView.setSelectedRange(NSRange(location: 6, length: 0))
            editor.textView.insertText("/", replacementRange: NSRange(location: 6, length: 0))
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            check("slash menu: a slash mid-word is left alone", !editor.isSlashMenuOpen, "")
        }

        controller.loadText(text)
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = controller.editor.scrollView
        let clip = scrollView.contentView

        // --- Scrolling past the end -----------------------------------------
        check("clip view is the typewriter clip view",
              clip is TypewriterClipView, String(describing: type(of: clip)))

        let slack = (clip as? TypewriterClipView)?.bottomSlack ?? 0
        check("scroll slack reserved", slack > 100, "slack \(Int(slack))pt")

        let documentHeight = controller.editor.textView.frame.height
        let viewport = clip.bounds.height
        let plainMax = max(0, documentHeight - viewport)
        clip.scroll(to: NSPoint(x: 0, y: documentHeight))
        scrollView.reflectScrolledClipView(clip)
        let reached = clip.bounds.origin.y
        check("can scroll past the last line", reached > plainMax + 20,
              "reached \(Int(reached)) of plain max \(Int(plainMax))")

        // --- Typing does not move the page ------------------------------------
        do {
            let editor = controller.editor
            check("layout is contiguous",
                  editor.textView.layoutManager?.allowsNonContiguousLayout == false, "")

            let wasTypewriter = ThemeManager.shared.typewriterScrolling
            ThemeManager.shared.typewriterScrolling = false
            controller.loadText(String(repeating: "A line of the document.\n\n", count: 200))
            controller.view.layoutSubtreeIfNeeded()

            // Somewhere in the middle, then type.
            let middle = (editor.text as NSString).length / 2
            editor.textView.setSelectedRange(NSRange(location: middle, length: 0))
            editor.textView.scrollRangeToVisible(NSRange(location: middle, length: 0))
            controller.view.layoutSubtreeIfNeeded()
            let before = editor.scrollView.contentView.bounds.origin.y

            for _ in 0..<40 {
                let caret = editor.textView.selectedRange()
                editor.textView.insertText("x", replacementRange: caret)
            }
            controller.view.layoutSubtreeIfNeeded()
            let after = editor.scrollView.contentView.bounds.origin.y
            check("typing leaves the page where it was", abs(after - before) < 2,
                  "moved \(Int(after - before))pt over 40 keystrokes")

            // And the document is still all there and still styled.
            let styled = editor.textView.textStorage.map { storage -> Bool in
                guard storage.length > 0 else { return false }
                let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                return font != nil
            } ?? false
            check("the page is still drawn after typing", styled, "")

            ThemeManager.shared.typewriterScrolling = wasTypewriter
        }

        // --- Translucent palettes ---------------------------------------------
        // Every piece of the chain has to be right for a glass theme to read as
        // glass: a see-through window, a backdrop behind the page, a scroll view
        // that paints nothing, and a page colour that is not fully opaque.
        let previousPalette = ThemeManager.shared.activePaletteID
        ThemeManager.shared.selectPalette(id: "frost")
        let glassWindow = DocumentWindowController.create()
        glassWindow.window?.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        glassWindow.showWindow(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        if let glassController = glassWindow.contentViewController as? DocumentViewController {
            check("glass: window is see-through", glassWindow.window?.isOpaque == false)
            check("glass: window background is clear",
                  glassWindow.window?.backgroundColor.alphaComponent == 0)
            check("glass: backdrop is showing", glassController.hasVisibleBackdrop)
            check("glass: palette tint is over it", glassController.hasVisibleTint)
            check("glass: scroll view paints nothing",
                  glassController.editor.scrollView.drawsBackground == false)
            let alpha = ThemeManager.shared.theme.colors.page.alphaComponent
            check("glass: page is translucent", alpha < 0.95,
                  "page alpha \(String(format: "%.2f", alpha))")
            check("system scroll edge effect requested", glassWindow.hasSoftScrollEdge)

            // Half the materials are documented as opaque, and picking one of
            // those is indistinguishable from having no glass at all.
            let opaqueMaterials: Set<NSVisualEffectView.Material> = [
                .windowBackground, .contentBackground, .underWindowBackground, .underPageBackground,
            ]
            let material = ThemeManager.shared.theme.colors.material
            check("glass: material is a translucent one",
                  !opaqueMaterials.contains(material), "material \(material.rawValue)")
            let colors = ThemeManager.shared.theme.colors
            check("glass: panels are translucent too",
                  colors.codeBackground.alphaComponent < 0.5
                    && colors.tableHeaderBackground.alphaComponent < 0.5
                    && colors.backgroundElevated.alphaComponent < 0.5,
                  "code panel alpha \(String(format: "%.2f", colors.codeBackground.alphaComponent))")
            check("glass: tint is light enough to see through",
                  ThemeManager.shared.theme.colors.pageAlpha < 0.4,
                  "tint \(String(format: "%.2f", ThemeManager.shared.theme.colors.pageAlpha))")
        } else {
            check("glass: window builds", false)
        }
        glassWindow.close()
        ThemeManager.shared.selectPalette(id: previousPalette)

        // --- Centred title ----------------------------------------------------
        controller.documentTitle = "Notes.md"
        clip.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clip)
        controller.viewportMovedForTest()
        let atTop = controller.titleAlphaForTest

        clip.scroll(to: NSPoint(x: 0, y: 400))
        scrollView.reflectScrolledClipView(clip)
        controller.viewportMovedForTest()
        let scrolledAway = controller.titleAlphaForTest

        check("title shows at the top of the document", atTop > 0.9,
              "alpha \(String(format: "%.2f", atTop))")
        check("title goes once scrolled", scrolledAway < 0.1,
              "alpha \(String(format: "%.2f", scrolledAway))")
        check("window title bar is empty",
              glassWindow.window?.titleVisibility == .hidden)

        // --- Stale decorations --------------------------------------------------
        // Decorations are built from a parse and drawn later; a deletion in
        // between leaves ranges pointing past the end of the text. Asking the
        // layout manager about those raises, and AppKit turns a raise during
        // drawing into a crash, so drawing with impossible ranges has to be
        // survivable.
        let stale = NSRange(location: 900_000, length: 500)
        controller.editor.textView.decorations = [
            BlockDecoration(kind: .codeBlock, lineRanges: [stale], quoteDepth: 0),
            BlockDecoration(kind: .blockquote(depth: 1), lineRanges: [stale], quoteDepth: 1),
        ]
        controller.editor.textView.overlays = [
            .checkbox(stale, .open),
            .bullet(stale),
            .calloutTitle(stale, .note),
        ]
        check("a rect for a range past the end is refused",
              controller.editor.textView.rect(for: stale) == nil)
        // Drawing needs a context of its own here: there is no window on screen
        // to provide one, and `renderPage` paints straight into whatever is
        // current.
        func drawIntoBitmap(_ body: () -> Void) {
            let size = NSSize(width: 600, height: 300)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 600, pixelsHigh: 300,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(
                cgContext: context.cgContext, flipped: true)
            body()
            NSGraphicsContext.restoreGraphicsState()
        }

        let page = NSRect(x: 0, y: 0, width: 600, height: 300)
        drawIntoBitmap { controller.editor.textView.renderPage(page) }
        check("drawing survives stale decorations", true)

        // --- Chrome ----------------------------------------------------------
        let dragAreas = controller.view.subviews.compactMap { $0 as? WindowDragArea }
        check("window drag strip present", dragAreas.count == 1)
        check("drag strip covers the title bar",
              (dragAreas.first?.frame.height ?? 0) >= 40
                && (dragAreas.first?.frame.width ?? 0) > 400,
              dragAreas.first.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none")
        check("drag strip sits above the editor",
              controller.view.subviews.firstIndex(where: { $0 is WindowDragArea })
                ?? 0 > (controller.view.subviews.firstIndex(where: { $0 === controller.editor.view }) ?? 0))

        let bars = controller.view.subviews.compactMap { $0 as? DisplayOptionsBar }
        check("display options bar present", bars.count == 1)

        // --- Palette popover contents ----------------------------------------
        for section in OptionsPalette.Section.allCases {
            let palette = OptionsPalette(section: section)
            let built = palette.view.subviews.first?.subviews.count ?? 0
            check("palette builds: \(section.title)", built > 0, "\(built) rows")
        }

        say(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }

    // MARK: - Tables

    /// Tables are aligned by padding the source, so the padding is the thing
    /// worth testing: if it is right, the columns are right.
    private static func checkTables(_ check: (String, Bool, String) -> Void) {
        let ragged = """
        | Feature | Shortcut | Notes |
        | --- | ---: | :-: |
        | Bold | Cmd B | Wraps a word |
        | A much longer feature | X | y |
        """
        let padded = TableFormatter.normalized(ragged) ?? ragged
        let rows = padded.components(separatedBy: "\n")

        check("table: every row is the same width",
              Set(rows.map(\.count)).count == 1, "widths \(rows.map(\.count))")
        check("table: padding is idempotent",
              TableFormatter.normalized(padded) == nil, "")
        check("table: right alignment is kept",
              rows.count > 1 && rows[1].contains("-:"), rows.count > 1 ? rows[1] : "")
        check("table: centre alignment is kept",
              rows.count > 1 && rows[1].contains(":-"), rows.count > 1 ? rows[1] : "")

        let parsed = MarkdownParser.parse(padded as NSString)
        let kinds = parsed.lines.prefix(4).map(\.kind)
        check("table: header row found", kinds.first == .tableRow(header: true), "")
        check("table: delimiter row found", kinds.count > 1 && kinds[1] == .tableDelimiter, "")
        check("table: body rows found",
              kinds.count > 3 && kinds[2] == .tableRow(header: false)
                && kinds[3] == .tableRow(header: false), "")

        // An empty header is legal and must not collapse the column count.
        let empty = TableFormatter.cells("| | |")
        check("table: empty cells keep their columns", empty.count == 2, "\(empty.count) cells")

        // A pipe written as text belongs to the cell, not to the grid.
        let escaped = TableFormatter.cells(#"| a \| b | c |"#)
        check("table: escaped pipes stay in the cell", escaped.count == 2, "\(escaped.count) cells")

        // A run of dashes on its own is still a rule, not a table.
        let rule = MarkdownParser.parse("Some text\n---\n" as NSString)
        check("table: a bare rule is not a table",
              !rule.lines.contains { $0.kind.isTable }, "")
    }

}

import AppKit

/// Runtime checks for the parts of the interface a screenshot cannot show.
///
///     Kvill --selftest [document.md]
///
/// The floating chrome is built from glass and visual-effect views, which never
/// render in an off-screen window, so the only honest way to know whether they
/// are wired up is to build the real view tree, lay it out, and interrogate it.
/// A window that stays where it is put.
///
/// AppKit drags an off-screen window back onto the display when it is ordered
/// front, so every window the checks built for layout appeared in front of
/// whatever was on screen, and one was still there when they finished. Nothing
/// here is meant to be looked at.
private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

enum SelfTest {

    static func run(document: String?) -> Int32 {
        var failures = 0

        // Straight to stderr: buffered stdout is lost if a check crashes, which
        // hides the very line that would say where.
        func say(_ line: String) {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        /// Takes a window off screen the moment a check has opened one.
        ///
        /// The checks open real documents, and a real document arrives in a
        /// visible, centred window. Running them put a handful of windows in
        /// front of whatever was there. Ordered out they still lay out, which is
        /// all the checks want from them.
        func hide(_ document: NSDocument?) {
            document?.windowControllers.forEach { $0.window?.orderOut(nil) }
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
        check("palettes registered", ids.count == 6, ids.joined(separator: ", "))


        // --- The real view tree ---------------------------------------------
        let controller = DocumentViewController()
        let window = OffscreenWindow(
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

        // --- An empty document says what to do --------------------------------
        do {
            controller.loadText("")
            controller.view.layoutSubtreeIfNeeded()
            check("an empty document has a placeholder",
                  controller.editor.textView.placeholderForTest != nil, "")
            controller.loadText("x")
            controller.view.layoutSubtreeIfNeeded()
            check("a document with anything in it has none",
                  controller.editor.textView.placeholderForTest == nil, "")
        }

        // --- Checkbox and bullet sit on the same line -------------------------
        do {
            let editor = controller.editor
            controller.loadText("- [ ] An open task\n- [x] A finished one\n")
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))

            var bullet: NSRect?
            var checkbox: NSRect?
            for overlay in editor.textView.overlays {
                switch overlay {
                case .bullet(let range):
                    if bullet == nil { bullet = editor.textView.rect(for: range) }
                case .checkbox(let range, _):
                    if checkbox == nil { checkbox = editor.textView.rect(for: range) }
                default:
                    break
                }
            }
            say("    bullet \(bullet.map { "\(Int($0.minY))..\(Int($0.maxY)) mid \($0.midY)" } ?? "none")")
            say("    checkbox \(checkbox.map { "\(Int($0.minY))..\(Int($0.maxY)) mid \($0.midY)" } ?? "none")")
            check("checkbox and bullet share a centre line",
                  abs((bullet?.midY ?? 0) - (checkbox?.midY ?? 99)) < 0.51,
                  "difference \(((checkbox?.midY ?? 0) - (bullet?.midY ?? 0)))pt")
        }

        // --- Staying resident -------------------------------------------------
        do {
            // Written straight to defaults rather than through
            // BackgroundService.isEnabled, whose setter registers a real login
            // item. A test has no business changing what starts on someone's
            // machine, and an earlier version of this left one behind.
            let key = "kvill.staysRunning"
            let was = UserDefaults.standard.bool(forKey: key)
            let delegate = AppDelegate()

            UserDefaults.standard.set(false, forKey: key)
            check("background: off means the app quits with its last window",
                  delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp), "")
            check("background: off still opens a blank document on its own",
                  delegate.applicationShouldOpenUntitledFile(NSApp), "")

            UserDefaults.standard.set(true, forKey: key)
            check("background: on keeps the app alive with no windows",
                  !delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp), "")
            check("background: on still opens one when a person opens the app",
                  delegate.applicationShouldOpenUntitledFile(NSApp), "")

            // The login branch, which no test can reach through the real clock.
            check("launch: at login it opens nothing",
                  !AppDelegate.opensBlankDocument(backgroundEnabled: true, secondsSinceLogin: 3))
            check("launch: opened by a person later, it opens a document",
                  AppDelegate.opensBlankDocument(backgroundEnabled: true, secondsSinceLogin: 4000))
            check("launch: with the setting off it always opens one",
                  AppDelegate.opensBlankDocument(backgroundEnabled: false, secondsSinceLogin: 3))
            check("launch: an unreadable session start errs towards a window",
                  AppDelegate.opensBlankDocument(backgroundEnabled: true, secondsSinceLogin: nil))

            UserDefaults.standard.set(was, forKey: key)
            check("background: the test left no login item behind",
                  !BackgroundService.hasLoginItem || was,
                  BackgroundService.loginItemStatus)
        }

        // --- The file tree ----------------------------------------------------
        do {
            // A folder with Markdown at two levels, plus a file that should not
            // be listed and a folder holding nothing that should not appear.
            let root = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("kvill-tree-\(ProcessInfo.processInfo.processIdentifier)")
            let nested = root.appendingPathComponent("nested")
            let empty = root.appendingPathComponent("empty")
            try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
            try? "# one".write(to: root.appendingPathComponent("one.md"),
                               atomically: true, encoding: .utf8)
            try? "# two".write(to: nested.appendingPathComponent("two.md"),
                               atomically: true, encoding: .utf8)
            try? "not markdown".write(to: root.appendingPathComponent("notes.rtf"),
                                      atomically: true, encoding: .utf8)

            let tree = FileTreeView()
            tree.show(root)
            let listed = tree.listedForTest
            check("file tree: lists the Markdown", listed.contains("one"), listed.joined(separator: ", "))
            check("file tree: descends into folders", listed.contains("two"),
                  listed.joined(separator: ", "))
            check("file tree: leaves other files out", !listed.contains("notes"),
                  listed.joined(separator: ", "))
            check("file tree: leaves empty folders out", !listed.contains("empty"),
                  listed.joined(separator: ", "))

            check("file tree: opening a folder grants what is inside it",
                  FolderAccess.isReachable(nested.appendingPathComponent("two.md")), "")

            // A blank sidebar and a broken sidebar look identical, so the rows
            // themselves are counted: root, nested, the file inside it, one.md.
            tree.prepareForRender()
            check("file tree: shows a row per document", tree.rowCountForTest == 3,
                  "rows: \(tree.rowCountForTest)")

            let split = DocumentSplitViewController(page: DocumentViewController())
            _ = split.view
            check("file tree: the sidebar is hidden until a folder is opened",
                  !split.isShowingFileTree, "")
            split.showFolder(root)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("file tree: opening a folder puts the sidebar up",
                  split.isShowingFileTree, "")

            // A render is a read. Rendering with a theme used to leave the user's
            // own copy of Kvill set to it.
            let palette = UserDefaults.standard.string(forKey: "kvill.palette")
            let colors = ThemeManager.shared.theme.colors.id
            let saved = ThemeManager.shared.settingsSnapshot
            ThemeManager.shared.selectPalette(id: Palettes.nord.id)
            // Without this the restore check would pass on a setter that never
            // wrote anything, which is the whole reason the snapshot exists.
            let changed = UserDefaults.standard.string(forKey: "kvill.palette")
            check("display settings: choosing a palette is written to disk",
                  changed == Palettes.nord.id, changed ?? "unset")
            ThemeManager.shared.restore(saved)
            check("display settings: a snapshot puts the saved setting back",
                  UserDefaults.standard.string(forKey: "kvill.palette") == palette,
                  "was \(palette ?? "unset"), now "
                    + (UserDefaults.standard.string(forKey: "kvill.palette") ?? "unset"))
            check("display settings: a snapshot puts the live theme back too",
                  ThemeManager.shared.theme.colors.id == colors,
                  "was \(colors), now \(ThemeManager.shared.theme.colors.id)")

            FolderAccess.forget(root)
            try? FileManager.default.removeItem(at: root)
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
            check("slash menu: rows are menu height",
                  panel.rowHeightForTest == 30, "\(Int(panel.rowHeightForTest))pt")
            check("slash menu: the chosen row reads as chosen",
                  panel.selectedRowIsHighlightedForTest, "")
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

        // The height is measured a moment after a document loads, not during.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))

        // Scrolling past the end, checked through a route that actually
        // constrains. `NSClipView.scroll(to:)` does not: it sets the bounds
        // origin to whatever it is handed, so a check built on it passes by
        // landing where it asked and proves nothing. `scrollToEndOfDocument` is
        // the real thing, the same call Cmd Down makes.
        controller.view.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let line = ThemeManager.shared.theme.metrics.lineHeight
        let used = controller.editor.textView.layoutManager.flatMap { manager in
            controller.editor.textView.textContainer.map { manager.usedRect(for: $0).height }
        } ?? 0
        let content = used + controller.editor.textView.textContainerInset.height * 2
        let viewport = clip.bounds.height
        let grown = controller.editor.textView.frame.height - content
        check("the text view is taller than its text",
              grown > viewport / 2,
              "taller by \(Int(grown))pt, window \(Int(viewport))pt")

        clip.scroll(to: .zero)
        scrollView.reflectScrolledClipView(clip)
        controller.editor.textView.scrollToEndOfDocument(nil)
        controller.view.layoutSubtreeIfNeeded()
        let reached = clip.bounds.origin.y
        let plainMax = max(0, content - viewport)
        check("scrolling to the end goes past the last line",
              reached > plainMax + 20,
              "reached \(Int(reached)), last line at the bottom would be \(Int(plainMax))")
        // The reachable bottom is the view's height less a window, and the rule
        // says that lands with the last line at the top.
        let inset = controller.editor.textView.textContainerInset.height
        let maxScroll = controller.editor.textView.frame.height - viewport
        // Stopping with the last line where a first line sits, not at the edge.
        // The inset carries that margin, so it is an inset that comes off.
        let expected = max(0, used - line)
        check("the last line stops where a first line sits",
              abs(maxScroll - expected) < 3,
              "max scroll \(Int(maxScroll)), expected \(Int(expected))")

        // A document that fits has nowhere to go.
        controller.loadText("")
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        check("an empty document does not scroll",
              controller.editor.textView.frame.height <= viewport + 1,
              "view \(Int(controller.editor.textView.frame.height))pt, window \(Int(viewport))pt")
        controller.loadText(text)
        controller.view.layoutSubtreeIfNeeded()

        // --- Scroll past end is a setting -------------------------------------
        do {
            let manager = ThemeManager.shared
            let was = manager.scrollPastEnd
            let wasTypewriter = manager.typewriterScrolling
            manager.typewriterScrolling = false
            manager.scrollPastEnd = false
            controller.view.layoutSubtreeIfNeeded()
            // The height is measured a moment after a change rather than on
            // every keystroke, so the check waits the same moment.
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            let flat = controller.editor.textView.frame.height - content
            check("scroll past end: off leaves no room below the text",
                  flat < line + 3, "taller by \(Int(flat))pt")

            manager.scrollPastEnd = true
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("scroll past end: on leaves a window of room",
                  controller.editor.textView.frame.height - content > 100, "")

            // Typewriter mode needs the room whatever the setting says.
            manager.scrollPastEnd = false
            manager.typewriterScrolling = true
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("scroll past end: typewriter keeps half a window anyway",
                  controller.editor.textView.frame.height - content > 100,
                  "taller by \(Int(controller.editor.textView.frame.height - content))pt")

            manager.scrollPastEnd = was
            manager.typewriterScrolling = wasTypewriter
        }

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
        let documentWindow = DocumentWindowController.create()
        check("window title bar is empty",
              documentWindow.window?.titleVisibility == .hidden)
        // Closed again. It was left on screen, so running the checks put a
        // stray empty window in front of whatever was there.
        documentWindow.window?.orderOut(nil)
        documentWindow.close()


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
        // Looked for wherever it lives rather than as a direct child of the
        // pane: on a translucent palette the page is a card inset inside its
        // pane, and everything moved a level down with it.
        func chrome(of controller: DocumentViewController) -> [NSView] {
            var found: [NSView] = []
            func walk(_ view: NSView) {
                found.append(view)
                view.subviews.forEach(walk)
            }
            controller.view.subviews.forEach(walk)
            return found
        }
        let pageChrome = chrome(of: controller)
        let dragAreas = pageChrome.compactMap { $0 as? WindowDragArea }
        check("window drag strip present", dragAreas.count == 1)
        check("drag strip covers the title bar",
              (dragAreas.first?.frame.height ?? 0) >= 40
                && (dragAreas.first?.frame.width ?? 0) > 400,
              dragAreas.first.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none")
        check("drag strip sits above the editor",
              (pageChrome.firstIndex(where: { $0 is WindowDragArea }) ?? 0)
                > (pageChrome.firstIndex(where: { $0 === controller.editor.view }) ?? 0))

        let bars = pageChrome.compactMap { $0 as? DisplayOptionsBar }
        check("display options bar present", bars.count == 1)

        // --- Palette popover contents ----------------------------------------
        for section in OptionsPalette.Section.allCases {
            let palette = OptionsPalette(section: section)
            let built = palette.view.subviews.first?.subviews.count ?? 0
            check("palette builds: \(section.title)", built > 0, "\(built) rows")
        }

        // --- Two open files never touch each other's contents -------------
        // The regression that matters most in this app. A view controller was
        // once shared between documents so a window could be reused when
        // switching files in the sidebar. `data(ofType:)` reads the text out of
        // the view controller, so the document being replaced autosaved the
        // incoming file's text into its own path. Four notes ended up holding
        // each other's contents, two of them identical, with stray keystrokes in
        // the wrong files. This opens two documents, types a distinct line into
        // each, saves both, and reads the bytes back off disk.
        do {
            let documentController = (NSDocumentController.shared as? KvillDocumentController)
                ?? KvillDocumentController()
            let folder = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("kvill-isolation-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let files = ["Alpha.md": "# Alpha\n\nAlpha body.\n",
                         "Beta.md": "# Beta\n\nBeta body.\n"]
            for (name, body) in files {
                try? body.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
            }
            let settled = { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }

            var opened: [String: NSDocument] = [:]
            for name in files.keys.sorted() {
                documentController.openDocument(
                    withContentsOf: folder.appendingPathComponent(name), display: true
                ) { document, _, _ in
                    if let document { opened[name] = document }
                    hide(document)
                }
                settled()
            }

            check("isolation: both files opened", opened.count == 2, "\(opened.count)")
            check("isolation: each file got its own window",
                  Set(opened.values.compactMap { $0.windowControllers.first }).count == 2)
            check("isolation: each window got its own editor",
                  Set(opened.values.compactMap {
                      ($0.windowControllers.first?.contentViewController
                        as? DocumentSplitViewController).map { ObjectIdentifier($0.page) }
                  }).count == 2)

            // Type something only ever typed into this one, then save both.
            for (name, document) in opened {
                let editor = (document.windowControllers.first?
                    .contentViewController as? DocumentSplitViewController)?.page
                editor?.editor.textView.insertText(
                    "\nTyped into \(name)\n",
                    replacementRange: NSRange(location: 0, length: 0))
                document.updateChangeCount(.changeDone)
            }
            settled()
            for document in opened.values {
                document.save(withDelegate: nil, didSave: nil, contextInfo: nil)
            }
            settled()
            settled()

            for name in files.keys.sorted() {
                let onDisk = (try? String(
                    contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
                let other = files.keys.first { $0 != name } ?? ""
                let flat = onDisk.replacingOccurrences(of: "\n", with: "\u{23CE}")
                check("isolation: \(name) was actually written and read back",
                      onDisk.count > 20, "\(onDisk.count) bytes")
                check("isolation: \(name) still holds its own text",
                      onDisk.contains("Typed into \(name)"), String(flat.prefix(50)))
                check("isolation: \(name) holds none of \(other)",
                      !onDisk.contains("Typed into \(other)")
                        && !onDisk.contains("# \(other.dropLast(3))"),
                      String(flat.prefix(50)))
            }

            opened.values.forEach { $0.close() }

            // --- and the same again, switching inside one window --------------
            // The way the corruption actually happened. Type into a file, switch
            // the window to another file, type into that, and both files must
            // still hold only their own text.
            let gamma = folder.appendingPathComponent("Gamma.md")
            let delta = folder.appendingPathComponent("Delta.md")
            try? "# Gamma\n\nGamma body.\n".write(to: gamma, atomically: true, encoding: .utf8)
            try? "# Delta\n\nDelta body.\n".write(to: delta, atomically: true, encoding: .utf8)

            var first: NSDocument?
            documentController.openDocument(withContentsOf: gamma, display: true) { d, _, _ in
                first = d
                hide(d)
            }
            settled()

            if let one = first, let window = one.windowControllers.first?.window {
                let editorOne = (window.contentViewController as? DocumentSplitViewController)?.page
                editorOne?.editor.textView.insertText(
                    "GAMMA-ONLY\n", replacementRange: NSRange(location: 0, length: 0))
                one.updateChangeCount(.changeDone)

                let switched = documentController.openInPlace(delta, replacing: one)
                check("switch: the window took the second file", switched)
                settled()

                let editorTwo = (window.contentViewController as? DocumentSplitViewController)?.page
                check("switch: it is showing the file that was clicked",
                      editorTwo?.documentURL?.lastPathComponent == "Delta.md",
                      editorTwo?.documentURL?.lastPathComponent ?? "nothing")
                check("switch: the incoming file brought its own editor",
                      editorTwo !== editorOne)
                // Counted from the documents, not from NSApp.windows: this test
                // harness opens a bare editor window of its own at the top, and
                // counting every window with an editor in it counted that too.
                let documentWindows = documentController.documents
                    .compactMap { $0.windowControllers.first?.window }
                    .filter { $0.isVisible }
                check("switch: no second window appeared",
                      documentWindows.count <= 1, "\(documentWindows.count)")

                editorTwo?.editor.textView.insertText(
                    "DELTA-ONLY\n", replacementRange: NSRange(location: 0, length: 0))
                documentController.document(for: window)?.updateChangeCount(.changeDone)
                settled()
                documentController.documents.forEach {
                    $0.save(withDelegate: nil, didSave: nil, contextInfo: nil)
                }
                settled(); settled()

                // Through the sidebar's own callback, which is the path a click
                // takes. Calling openInPlace directly checks the mechanism but
                // not the wiring, and the wiring is what broke: files opened in
                // their own windows again while every direct check passed.
                let windowsBefore = documentController.documents
                    .compactMap { $0.windowControllers.first?.window }
                    .filter { $0.isVisible }.count
                if let hostSplit = window.contentViewController as? DocumentSplitViewController {
                    hostSplit.openFromSidebarForTest(gamma)
                    settled()
                    let after = documentController.documents
                        .compactMap { $0.windowControllers.first?.window }
                        .filter { $0.isVisible }.count
                    check("sidebar: choosing a file opens no second window",
                          after <= windowsBefore, "\(windowsBefore) -> \(after)")
                    check("sidebar: and the window it is in shows that file",
                          (window.contentViewController as? DocumentSplitViewController)?
                            .page.documentURL?.lastPathComponent == "Gamma.md",
                          (window.contentViewController as? DocumentSplitViewController)?
                            .page.documentURL?.lastPathComponent ?? "nothing")
                } else {
                    check("sidebar: the window holds a split view", false)
                }

                let g = (try? String(contentsOf: gamma, encoding: .utf8)) ?? ""
                let d = (try? String(contentsOf: delta, encoding: .utf8)) ?? ""
                check("switch: Gamma.md kept the text typed into it",
                      g.contains("GAMMA-ONLY"), "\(g.count) bytes")
                check("switch: Gamma.md did not take Delta's text",
                      !g.contains("DELTA-ONLY") && !g.contains("# Delta"), "\(g.count) bytes")
                check("switch: Delta.md kept the text typed into it",
                      d.contains("DELTA-ONLY"), "\(d.count) bytes")
                check("switch: Delta.md did not take Gamma's text",
                      !d.contains("GAMMA-ONLY") && !d.contains("# Gamma"), "\(d.count) bytes")
            } else {
                check("switch: a document opened to switch away from", false)
            }

            documentController.documents.forEach { $0.close() }
            try? FileManager.default.removeItem(at: folder)
        }

        // --- The sidebar is AppKit's, and the page is never under it ----------
        // Reported as the content snapping to the wrong side: a hand-written
        // sidebar moved the page left and then covered it. It is an
        // NSSplitViewItem now, so collapsing, the width limits, the animation
        // and the divider are the system's. What is still worth checking is that
        // it is genuinely the standard component and that the page is beside it
        // rather than beneath it.
        do {
            // The app's own window, not a bare NSWindow assembled here. The
            // hand-built one had no opaque background and no title bar setup, so
            // it drew a see-through border around the sidebar: a thing that only
            // ever existed inside the checks, which is the worst kind of thing to
            // be looking at when judging how the app looks.
            let host = DocumentWindowController.create()
            guard let split = host.window?.contentViewController
                    as? DocumentSplitViewController else {
                check("sidebar: the app's window holds a split view", false)
                return failures == 0 ? 0 : 1
            }
            host.window?.setContentSize(NSSize(width: 1200, height: 800))

            let folder = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("kvill-sidebar-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? "# One\n".write(to: folder.appendingPathComponent("One.md"),
                                 atomically: true, encoding: .utf8)

            // One file first: a sidebar listing the document already on screen
            // is a list of one thing, so there is nothing to open and no button
            // offering to.
            split.showFolder(folder)
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("sidebar: a folder holding one file gets no sidebar",
                  !split.isShowingFileTree)
            check("sidebar: and nothing to switch between",
                  !split.hasSomethingToSwitchBetween)

            try? "# Two\n".write(to: folder.appendingPathComponent("Two.md"),
                                 atomically: true, encoding: .utf8)

            let items = split.splitViewItems
            check("sidebar: it is a real NSSplitViewItem sidebar",
                  items.first?.behavior == .sidebar, "\(items.count) items")
            check("sidebar: the page pane cannot be collapsed away",
                  items.last?.canCollapse == false)
            check("sidebar: it starts collapsed, before any folder is open",
                  items.first?.isCollapsed == true)

            split.showFolder(folder)
            // Uncollapsing is animated, so the pane has no width until it has
            // run. Reading the frames straight away measured a sidebar of zero.
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            split.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            split.view.layoutSubtreeIfNeeded()
            check("sidebar: opening a folder opens it", split.isShowingFileTree)

            // Geometry is measured with the collapse set directly rather than
            // through the animator. An off-screen window runs no animation, so
            // the pane stayed at zero width and the frames said the sidebar was
            // nowhere: a measurement of the test rig, not of the app.
            // An off-screen split view never divides itself, so the panes sat at
            // zero width and the frames reported the sidebar as nowhere: a
            // measurement of the rig rather than of the app. The divider is put
            // where a real window would put it, and the geometry checked from
            // there.
            // Uncollapsed through the animator, which in an off-screen window
            // never finishes: `isCollapsed` reads false while the layout never
            // ran, so setting it false again is a no-op and the pane keeps zero
            // width. A real transition, both ways, without the animator.
            split.splitViewItems.first?.isCollapsed = true
            split.view.layoutSubtreeIfNeeded()
            split.splitViewItems.first?.isCollapsed = false
            split.view.layoutSubtreeIfNeeded()

            // The reported bug, in the terms the split view makes available: the
            // page's frame must begin after the sidebar's, never inside it.
            let space = split.splitView
            let sidebarFrame = space.convert(split.sidebar.view.bounds, from: split.sidebar.view)
            let pageFrame = space.convert(split.page.view.bounds, from: split.page.view)
            check("sidebar: the page starts where the sidebar ends",
                  pageFrame.minX >= sidebarFrame.maxX - 1,
                  "sidebar to \(Int(sidebarFrame.maxX)), page from \(Int(pageFrame.minX))")
            check("sidebar: the page is not underneath it",
                  !pageFrame.intersects(sidebarFrame.insetBy(dx: 1, dy: 0)),
                  "page \(Int(pageFrame.minX))..\(Int(pageFrame.maxX))")

            // Collapsing gives the width back to the page, which is the whole
            // point of it being collapsible.
            let widthWithSidebar = split.page.view.frame.width
            split.splitViewItems.first?.isCollapsed = true
            split.splitView.adjustSubviews()
            split.view.layoutSubtreeIfNeeded()
            check("sidebar: collapsing gives the room to the page",
                  split.page.view.frame.width > widthWithSidebar,
                  "\(Int(widthWithSidebar)) -> \(Int(split.page.view.frame.width))")

            host.close()
            try? FileManager.default.removeItem(at: folder)
        }

        // Nothing this run opened may still be on screen. A check that leaves a
        // window behind is a check that changed the machine it ran on.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let leftBehind = NSApp.windows.filter {
            $0.isVisible && $0.frame.origin.x > -10000
        }
        check("the checks left no windows on screen", leftBehind.isEmpty,
              leftBehind.map {
                  "\(type(of: $0)) \(type(of: $0.contentViewController ?? NSViewController())) "
                    + "at \(Int($0.frame.origin.x)),\(Int($0.frame.origin.y))"
              }.joined(separator: " | "))

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

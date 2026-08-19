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

        // Every document window these checks open is built off screen and
        // transparent. Hiding them afterwards was not enough: AppKit had already
        // put them up, and a window that flashes for two frames in front of
        // whoever is using the machine is still a window in their face.
        DocumentWindowController.buildsHidden = true
        defer { DocumentWindowController.buildsHidden = false }

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

        // --- Code blocks and tables stay inside the window --------------------
        // The panels behind them were drawn from the typography preset's column
        // width, which is a fixed number that knows nothing about the window. In
        // a narrow window the text rewrapped to what fitted and the panel did
        // not, so it ran off the right edge.
        //
        // Measured from the rects the view actually painted, not from the same
        // sum worked out a second time here.
        do {
            controller.loadText("""
            Prose above.

            ```swift
            let x = compute(a, b)
            ```

            | Column | Another |
            | --- | --- |
            | 1 | 2 |

            > [!NOTE]
            > A callout, which has the widest padding of the lot.
            """)

            for width in [460.0, 620.0, 1200.0] as [CGFloat] {
                window.setContentSize(NSSize(width: width, height: 600))
                controller.view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
                let textView = controller.editor.textView
                textView.display()

                let panels = textView.drawnPanels
                check("panels at \(Int(width))pt: something was drawn to measure",
                      !panels.isEmpty, "\(panels.count) panels")
                let page = textView.bounds.width
                let overflowing = panels.filter { $0.maxX > page + 0.5 }
                check("panels at \(Int(width))pt: none runs past the right edge",
                      overflowing.isEmpty,
                      overflowing.isEmpty
                        ? "widest \(Int(panels.map(\.maxX).max() ?? 0)) of \(Int(page))"
                        : "\(overflowing.count) past \(Int(page)): "
                          + overflowing.map { Int($0.maxX).description }.joined(separator: ", "))
                check("panels at \(Int(width))pt: none starts off the left edge",
                      panels.allSatisfy { $0.minX >= -0.5 },
                      "leftmost \(Int(panels.map(\.minX).min() ?? 0))")

                // The panel has to clear the text on both sides. Clamping it to
                // where the text ended put a callout's last words on its own
                // border, padded on one side and not the other.
                // Only the right edge. On the left the panel starts at the text
                // column, which begins after the marker gutter, so comparing it
                // to the container's inset measures the gutter and calls a
                // correct panel wrong.
                let inset = textView.textContainerInset.width
                let textRight = page - inset
                let tight = panels.filter { $0.maxX < textRight + 1 }
                check("panels at \(Int(width))pt: the text sits inside them, not on the edge",
                      tight.isEmpty,
                      tight.isEmpty
                        ? "text ends \(Int(textRight)), panels \(Int(panels.map(\.maxX).min() ?? 0))+"
                        : "\(tight.count) panel(s) end before the text does")
            }
            window.setContentSize(NSSize(width: 900, height: 600))
            controller.view.layoutSubtreeIfNeeded()
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
            // The caret out of both lines, explicitly. Markers are revealed for
            // whichever element the caret is in, so a line holding the caret is
            // showing its source and is not the thing being measured. This used
            // to pass by accident, because loading a document left the caret at
            // the very end, and it started failing the day that was fixed.
            controller.editor.textView.setSelectedRange(
                NSRange(location: (controller.editor.text as NSString).length, length: 0))
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

            // A row can be dragged out. That is the whole gesture for opening a
            // second document beside the first, so a row that carries nothing on
            // the pasteboard is split mode with no way in.
            tree.prepareForRender()
            var draggableFiles = 0
            var draggableFolders = 0
            for row in 0..<tree.rowCountForTest where tree.pasteboardURLForTest(row: row) != nil {
                if tree.isFolderRowForTest(row) { draggableFolders += 1 } else { draggableFiles += 1 }
            }
            check("file tree: a file can be dragged out of the sidebar",
                  draggableFiles > 0, "\(draggableFiles) files")
            check("file tree: a folder cannot, since two folders is not a split",
                  draggableFolders == 0, "\(draggableFolders) folders")

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
        // landing where it asked and proves nothing.
        //
        // `moveToEndOfDocument` is the call Cmd Down makes in a text view, and
        // it is the one used here. `scrollToEndOfDocument` was used before and
        // is a no-op on `NSTextView`: measured on a real document window it
        // left the origin at 0 while `moveToEndOfDocument` reached 3187 of a
        // possible 3444, and `NSScrollView` does not implement the selector at
        // all. A check calling it was asking a question nothing answers.
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
        controller.editor.textView.moveToEndOfDocument(nil)
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

        // --- Nothing paints a bar across the top --------------------------------
        // Two bands shipped, one windowed and one in full screen, and both were
        // this app painting something the system had left alone.
        //
        // The windowed one was the scroll edge accessory given a background
        // colour: an opaque strip over the sidebar's shadow and over any line
        // scrolled under it, which cut a heading in half. The accessory is
        // there to be scrolled behind, so it must draw nothing at all.
        let accessories = documentWindow.window?.titlebarAccessoryViewControllers ?? []
        check("the scroll edge strip draws nothing",
              accessories.allSatisfy { $0.view.layer?.backgroundColor == nil },
              "\(accessories.count) accessories")

        // The full screen one was the empty toolbar. AppKit keeps a toolbar on
        // screen in full screen, and this window's title bar is transparent
        // with no window behind it there, so the strip came out black.
        if let window = documentWindow.window {
            let options = documentWindow.window(window, willUseFullScreenPresentationOptions: [])
            check("full screen hides the toolbar until the pointer asks for it",
                  options.contains(.autoHideToolbar) && options.contains(.fullScreen)
                  && options.contains(.autoHideMenuBar), "\(options.rawValue)")
        }

        // --- What full screen does to the chrome --------------------------------
        // The strip that slides down when the pointer reaches the top edge is
        // the system's and cannot be done away with, but it does not have to be
        // twice the size. Measured on a real full screen window: 32 points of
        // title bar plus a 36 point scroll edge accessory is the 68 it came to,
        // and Apple's own note on `fullScreenMinHeight` says why zero does not
        // help — the accessory is clipped while hidden, never removed, so it is
        // back to full height the moment the strip is revealed. Taken out for
        // the length of full screen instead, and put back on the way out.
        if let window = documentWindow.window {
            let accessoriesBefore = window.titlebarAccessoryViewControllers.count
            documentWindow.windowWillEnterFullScreen(
                Notification(name: NSWindow.willEnterFullScreenNotification))
            check("full screen: nothing of ours is left in the strip",
                  window.toolbar == nil && window.titlebarAccessoryViewControllers.isEmpty,
                  "toolbar \(window.toolbar == nil ? "gone" : "still there"), "
                  + "\(window.titlebarAccessoryViewControllers.count) accessories")
            check("full screen: and the title bar is painted rather than clear",
                  !window.titlebarAppearsTransparent)

            documentWindow.windowDidExitFullScreen(
                Notification(name: NSWindow.didExitFullScreenNotification))
            check("full screen: the toolbar comes back on the way out",
                  window.toolbar != nil && window.toolbarStyle == .unified)
            check("full screen: and so does the scroll edge",
                  window.titlebarAccessoryViewControllers.count == accessoriesBefore,
                  "\(window.titlebarAccessoryViewControllers.count) of \(accessoriesBefore)")
            check("full screen: windowed is transparent again",
                  window.titlebarAppearsTransparent
                  && window.titlebarSeparatorStyle == .none)
        }

        // --- What full screen does to the chrome --------------------------------
        // The strip that slides down when the pointer reaches the top edge is
        // the system's and cannot be done away with, but it does not have to be
        // twice the size. Measured on a real full screen window: 32 points of
        // title bar plus a 36 point scroll edge accessory came to 68, and
        // Apple's note on `fullScreenMinHeight` says why zero does not help -
        // a hidden accessory is clipped, never removed, so it is back to full
        // height the moment the strip is revealed. Taken out for the length of
        // full screen instead, and put back on the way out. Measured again
        // after: 32.
        if let window = documentWindow.window {
            let accessoriesBefore = window.titlebarAccessoryViewControllers.count
            documentWindow.windowWillEnterFullScreen(
                Notification(name: NSWindow.willEnterFullScreenNotification))
            check("full screen: nothing of ours is left in the strip",
                  window.toolbar == nil && window.titlebarAccessoryViewControllers.isEmpty,
                  "toolbar \(window.toolbar == nil ? "gone" : "still there"), "
                  + "\(window.titlebarAccessoryViewControllers.count) accessories")
            check("full screen: and the title bar is painted rather than clear",
                  !window.titlebarAppearsTransparent)

            documentWindow.windowDidExitFullScreen(
                Notification(name: NSWindow.didExitFullScreenNotification))
            check("full screen: the toolbar comes back on the way out",
                  window.toolbar != nil && window.toolbarStyle == .unified)
            check("full screen: and so does the scroll edge",
                  window.titlebarAccessoryViewControllers.count == accessoriesBefore,
                  "\(window.titlebarAccessoryViewControllers.count) of \(accessoriesBefore)")
            check("full screen: windowed is transparent again",
                  window.titlebarAppearsTransparent
                  && window.titlebarSeparatorStyle == .none)
        }

        // The sidebar holds room at the top for the traffic lights. In full
        // screen they are in the strip rather than over the sidebar, so that
        // room is 44 points of nothing above the first file.
        // The sidebar covers AppKit's own container completely. Without an
        // opaque surface of its own the container samples what is behind the
        // window, and on a coloured desktop the sidebar comes out the colour of
        // the wallpaper.
        do {
            let bar = SidebarViewController()
            _ = bar.view
            check("sidebar: it paints an opaque surface rather than showing the desktop",
                  bar.paintsItsOwnSurfaceForTest)
            check("sidebar: and keeps the rounded panel and the shadow with it",
                  bar.drawsItsOwnPanelForTest)
            // Windowed the panel runs to the top, under the traffic lights. In
            // full screen there is no title bar and AppKit puts the sidebar
            // against the top of the display, so the panel starts where the
            // floating buttons start instead.
            check("sidebar: the panel runs to the top of a window",
                  SidebarViewController.panelTop(inFullScreen: false) == 0)
            check("sidebar: and lines up with the floating buttons in full screen",
                  SidebarViewController.panelTop(inFullScreen: true)
                      == DocumentViewController.chromeInset,
                  "\(SidebarViewController.panelTop(inFullScreen: true))")
        }

        check("sidebar: room for the traffic lights in a window",
              SidebarViewController.listTop(inFullScreen: false) == WindowDragArea.height)

        // The button that opens the sidebar keeps clear of the traffic lights,
        // and in full screen there are none to keep clear of.
        do {
            let collapsed = DocumentViewController.toggleLeading(
                pageStartsAt: 0, inFullScreen: false)
            let open = DocumentViewController.toggleLeading(
                pageStartsAt: 200, inFullScreen: false)
            let full = DocumentViewController.toggleLeading(
                pageStartsAt: 0, inFullScreen: true)
            check("toggle: clear of the traffic lights with the sidebar shut",
                  collapsed == DocumentViewController.toggleClearOfLights, "\(collapsed)")
            check("toggle: at the page's own margin once the sidebar is open",
                  open == DocumentViewController.toggleBesideText, "\(open)")
            check("toggle: and in the corner in full screen, where there are no lights",
                  full == DocumentViewController.toggleBesideText, "\(full)")
        }
        // In full screen there are no traffic lights over the sidebar, but the
        // strip that slides down from the top edge would cover the folder's
        // name, so the list starts where the strip ends.
        check("sidebar: in full screen it clears the strip instead",
              SidebarViewController.listTop(inFullScreen: true)
                  == SidebarViewController.revealedStrip
              && SidebarViewController.revealedStrip > 0,
              "\(SidebarViewController.listTop(inFullScreen: true))")

        // --- What full screen does to the chrome --------------------------------
        // The strip that slides down when the pointer reaches the top edge is
        // the system's and cannot be done away with, but it does not have to be
        // twice the size. Measured on a real full screen window, listing only
        // this app's own windows: the reveal was 68 points. 32 of that is the
        // title bar and the other 36 is the scroll edge accessory, and Apple's
        // note on `fullScreenMinHeight` says why zero does not help - a hidden
        // accessory is clipped by an internal clip view, never removed, so it
        // is back to full height the moment the strip is revealed. Taken out
        // for the length of full screen instead. Measured again: 32.
        if let window = documentWindow.window {
            let accessoriesBefore = window.titlebarAccessoryViewControllers.count
            documentWindow.windowWillEnterFullScreen(
                Notification(name: NSWindow.willEnterFullScreenNotification))
            check("full screen: nothing of ours is left in the strip",
                  window.toolbar == nil && window.titlebarAccessoryViewControllers.isEmpty,
                  "toolbar \(window.toolbar == nil ? "gone" : "still there"), "
                  + "\(window.titlebarAccessoryViewControllers.count) accessories")
            check("full screen: the title bar is painted rather than clear",
                  !window.titlebarAppearsTransparent)
            // FB20291636: a sidebar stops short of the top of the screen in
            // full screen while this is set, leaving a gap the height of the
            // strip above the file list.
            check("full screen: the full size content view is out of the way",
                  !window.styleMask.contains(.fullSizeContentView))
            check("full screen: the title bar height is remembered for the page",
                  documentWindow.windowedTitleBar > 0,
                  "\(documentWindow.windowedTitleBar)")

            documentWindow.windowDidExitFullScreen(
                Notification(name: NSWindow.didExitFullScreenNotification))
            check("full screen: the toolbar comes back on the way out",
                  window.toolbar != nil && window.toolbarStyle == .unified)
            check("full screen: and so does the scroll edge",
                  window.titlebarAccessoryViewControllers.count == accessoriesBefore,
                  "\(window.titlebarAccessoryViewControllers.count) of \(accessoriesBefore)")
            check("full screen: and the window is a window again",
                  window.titlebarAppearsTransparent
                  && window.titlebarSeparatorStyle == .none
                  && window.styleMask.contains(.fullSizeContentView))
        }

        // The sidebar holds room at the top for the traffic lights. In full
        // screen they are in the strip rather than over the sidebar, so that
        // room is 44 points of nothing above the first file.
        check("sidebar: room for the traffic lights in a window",
              SidebarViewController.listTop(inFullScreen: false) == WindowDragArea.height)

        // The button that opens the sidebar keeps clear of the traffic lights,
        // and in full screen there are none to keep clear of.
        do {
            let collapsed = DocumentViewController.toggleLeading(
                pageStartsAt: 0, inFullScreen: false)
            let open = DocumentViewController.toggleLeading(
                pageStartsAt: 200, inFullScreen: false)
            let full = DocumentViewController.toggleLeading(
                pageStartsAt: 0, inFullScreen: true)
            check("toggle: clear of the traffic lights with the sidebar shut",
                  collapsed == DocumentViewController.toggleClearOfLights, "\(collapsed)")
            check("toggle: at the page's own margin once the sidebar is open",
                  open == DocumentViewController.toggleBesideText, "\(open)")
            check("toggle: and in the corner in full screen, where there are no lights",
                  full == DocumentViewController.toggleBesideText, "\(full)")
        }
        // In full screen there are no traffic lights over the sidebar, but the
        // strip that slides down from the top edge would cover the folder's
        // name, so the list starts where the strip ends.
        check("sidebar: in full screen it clears the strip instead",
              SidebarViewController.listTop(inFullScreen: true)
                  == SidebarViewController.revealedStrip
              && SidebarViewController.revealedStrip > 0,
              "\(SidebarViewController.listTop(inFullScreen: true))")

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

        // --- Two documents in one window ---------------------------------------
        // Split mode. The failure to be afraid of is the one that already
        // happened once with a shared editor: two documents writing into each
        // other's files. So the check is not "are there two panes", it is "does
        // each file still hold only its own words after both have been typed
        // into and saved".
        do {
            let settled = { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("kvill-split-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(
                at: folder, withIntermediateDirectories: true)
            let left = folder.appendingPathComponent("Left.md")
            let right = folder.appendingPathComponent("Right.md")
            try? "# Left\n\nLeft body.\n".write(to: left, atomically: true, encoding: .utf8)
            try? "# Right\n\nRight body.\n".write(to: right, atomically: true, encoding: .utf8)

            var host: NSDocument?
            documentController.openDocument(withContentsOf: left, display: true) { d, _, _ in
                host = d
                hide(d)
            }
            settled()

            if let document = host, let window = document.windowControllers.first?.window,
               let split = window.contentViewController as? DocumentSplitViewController {
                let before = documentController.documents.count
                let opened = documentController.openBeside(right, in: window)
                settled()
                check("split: a document dropped on the page opens beside it", opened)
                check("split: the window is showing two", split.isSplit)
                check("split: and there are two documents open",
                      documentController.documents.count == before + 1,
                      "\(before) -> \(documentController.documents.count)")
                check("split: the second pane brought its own editor",
                      split.companion !== split.page && split.companion != nil)
                check("split: each pane is showing its own file",
                      split.page.documentURL?.lastPathComponent == "Left.md"
                      && split.companion?.documentURL?.lastPathComponent == "Right.md",
                      "\(split.page.documentURL?.lastPathComponent ?? "-") | "
                      + "\(split.companion?.documentURL?.lastPathComponent ?? "-")")
                check("split: the second pane offers no sidebar button of its own",
                      split.companion?.isCompanion == true && split.page.isCompanion == false)
                check("split: no second window appeared",
                      documentController.documents
                        .compactMap { $0.windowControllers.first?.window }
                        .filter { $0.isVisible }.count <= 1)

                // The same file on both sides is two editors on one text with no
                // way to keep them in step.
                check("split: the file already on the left is refused",
                      !documentController.openBeside(left, in: window))

                // Typing into both, then saving both.
                split.page.editor.textView.insertText(
                    "LEFT-ONLY\n", replacementRange: NSRange(location: 0, length: 0))
                split.companion?.editor.textView.insertText(
                    "RIGHT-ONLY\n", replacementRange: NSRange(location: 0, length: 0))
                documentController.documents.forEach { $0.updateChangeCount(.changeDone) }
                settled()
                documentController.documents.forEach {
                    $0.save(withDelegate: nil, didSave: nil, contextInfo: nil)
                }
                settled(); settled()

                let l = (try? String(contentsOf: left, encoding: .utf8)) ?? ""
                let r = (try? String(contentsOf: right, encoding: .utf8)) ?? ""
                check("split: Left.md kept the text typed into it", l.contains("LEFT-ONLY"))
                check("split: Left.md did not take Right's text",
                      !l.contains("RIGHT-ONLY") && !l.contains("# Right"), "\(l.count) bytes")
                check("split: Right.md kept the text typed into it", r.contains("RIGHT-ONLY"))
                check("split: Right.md did not take Left's text",
                      !r.contains("LEFT-ONLY") && !r.contains("# Left"), "\(r.count) bytes")

                // The one that would be silent data loss. A companion has no
                // window controller, and AppKit's autosave timer is started by
                // `updateChangeCount`, so whether it runs for a document with no
                // window is not something to assume. Typed, left alone for
                // longer than the half second autosave delay, then read off
                // disk.
                if let companion = split.companion,
                   let companionDocument = documentController.companionDocument(in: split) {
                    companion.editor.textView.insertText(
                        "AUTOSAVED\n", replacementRange: NSRange(location: 0, length: 0))
                    companionDocument.updateChangeCount(.changeDone)
                    RunLoop.current.run(until: Date().addingTimeInterval(1.6))
                    let written = (try? String(contentsOf: right, encoding: .utf8)) ?? ""
                    check("split: the second pane autosaves without a window of its own",
                          written.contains("AUTOSAVED"),
                          written.contains("AUTOSAVED") ? "" : "\(written.count) bytes on disk")
                }

                // Closing the split writes what was in it and lets its document
                // go, rather than leaving an invisible document open for ever.
                let openBefore = documentController.documents.count
                documentController.closeCompanion(in: split)
                settled(); settled()
                check("split: closing it leaves one pane", !split.isSplit)
                check("split: and closes the document that was in it",
                      documentController.documents.count == openBefore - 1,
                      "\(openBefore) -> \(documentController.documents.count)")
            } else {
                check("split: a document opened to split", false)
            }

            documentController.documents.forEach { $0.close() }
            try? FileManager.default.removeItem(at: folder)
        }

        // --- The About window ------------------------------------------------
        // Two columns: what the app is, and what is new. The real view tree is
        // built and interrogated, because a window that lays out wrong looks
        // exactly like a window that lays out right until someone opens it.
        do {
            let about = AboutPanel.makeContent()
            about.frame = NSRect(x: 0, y: 0, width: 680, height: 400)
            about.layoutSubtreeIfNeeded()

            func every(_ view: NSView) -> [NSView] {
                view.subviews + view.subviews.flatMap(every)
            }
            let all = every(about)
            let columns = all.compactMap { $0 as? NSStackView }
            check("about: it has two columns", columns.count >= 2, "\(columns.count)")

            let labels = all.compactMap { $0 as? NSTextField }.map(\.stringValue)
            check("about: it says what the app is called", labels.contains("Kvill"))
            check("about: and which version this is",
                  labels.contains { $0.hasPrefix("Version ") },
                  labels.first { $0.hasPrefix("Version ") } ?? "no version line")
            check("about: the new column is headed What's new",
                  labels.contains("What\'s new"))

            // Side by side, not stacked. Two columns that overlap are one column
            // with a layout bug.
            if columns.count >= 2 {
                let frames = columns.map { $0.convert($0.bounds, to: about) }
                    .sorted { $0.minX < $1.minX }
                check("about: the columns sit beside each other",
                      frames[0].maxX <= frames[1].minX + 1,
                      "\(Int(frames[0].maxX)) then \(Int(frames[1].minX))")
            }

            // The link, which is the part someone actually clicks.
            let made = AboutPanel.madeWithLove()
            var linked: URL?
            made.enumerateAttribute(.link, in: NSRange(location: 0, length: made.length)) {
                value, _, _ in
                if let url = value as? URL { linked = url }
            }
            check("about: made with love is credited", made.string.contains("Made with love by"))
            check("about: and baars.design is a real link",
                  linked == AboutPanel.siteURL, linked?.absoluteString ?? "no link")

            check("about: the name is explained",
                  AboutPanel.nameStory.lowercased().contains("quill"),
                  AboutPanel.nameStory)

            // The notes ship in the bundle, so a build that forgot the file is
            // caught here rather than by someone opening the window.
            let raw = AboutPanel.raw()
            check("about: the notes are in the bundle",
                  !raw.contains("not in it"),
                  raw.contains("not in it") ? "the file is missing from the app" : "")
            let entries = raw.components(separatedBy: "\n\n")
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("**") }
            check("about: there is something new to read", !entries.isEmpty, "\(entries.count) entries")

            for entry in entries {
                let lines = entry.split(separator: "\n").map(String.init)
                let title = lines.first ?? ""
                let name = title.replacingOccurrences(of: "**", with: "")
                    .components(separatedBy: " - ").first ?? ""
                check("about: \"\(name)\" carries a date",
                      title.contains(" - "), title)
                check("about: \"\(name)\" is two lines at most",
                      lines.count <= 3, "\(lines.count - 1) lines of text")
            }

            // The heading is a label and the notes are a text view, which pads
            // its lines by five points unless stopped. They looked aligned in
            // the code and were not on screen.
            let notesColumn = all.compactMap { $0 as? NSStackView }
                .first { column in
                    column.arrangedSubviews.contains { $0 is NSScrollView }
                }
            if let notesColumn,
               let headingLabel = notesColumn.arrangedSubviews.compactMap({ $0 as? NSTextField }).first,
               let scroller = notesColumn.arrangedSubviews.compactMap({ $0 as? NSScrollView }).first,
               let body = scroller.documentView as? NSTextView {
                // Measured from the alignment rect, not the frame. A stack view
                // lays an NSTextField out two points left of everything else on
                // purpose, because a label's alignment rect is inset from its
                // frame by exactly that much, so the text lands on the shared
                // edge. Comparing frames reported a two point gap that was not
                // on screen, and chasing it went looking for causes in the
                // scroll view twice.
                let headingFrame = headingLabel.convert(headingLabel.bounds, to: about)
                let headingX = headingLabel.alignmentRect(forFrame: headingFrame).origin.x
                let inset = body.textContainerInset.width
                    + (body.textContainer?.lineFragmentPadding ?? 0)
                let bodyX = body.convert(NSPoint.zero, to: about).x + inset
                check("about: the heading and the notes share a left edge",
                      abs(headingX - bodyX) < 0.5,
                      "heading \(headingX), notes \(bodyX)")
            } else {
                check("about: the notes column holds a heading and a body", false)
            }

            let rendered = AboutPanel.notes().string
            check("about: the notes render with their names",
                  rendered.contains("Live mode"), "")
            check("about: and their dates",
                  rendered.contains("August 2026"), "")
        }

        // --- Typewriter scrolling holds the line, wherever you are ------------
        // Reported as feeling unstable and sometimes scrolling to the bottom of
        // the page while typing. It did: the text view's height is recalculated
        // on a debounce, so during a burst of keystrokes the number the centring
        // clamped against was the old one, and pressing Return quickly at the
        // end of a document clamped to the bottom with the caret a third of a
        // page below the middle.
        //
        // Every case is driven through the real text view. The burst cases give
        // the run loop no turn between keys, which is what a person typing at
        // speed does and what the debounce hides.
        do {
            let manager = ThemeManager.shared
            let wasTypewriter = manager.typewriterScrolling
            let wasPastEnd = manager.scrollPastEnd
            manager.typewriterScrolling = true
            let editor = controller.editor

            /// Types into a document and reports how far the caret ended up from
            /// the middle of the window, and the largest single jump on the way.
            func typing(lines: Int, at where_: String, pastEnd: Bool, keys: Int,
                        newlines: Bool = false, deleting: Bool = false,
                        settling: Bool) -> (offCentre: CGFloat, jump: CGFloat, atTop: Bool) {
                manager.scrollPastEnd = pastEnd
                let body = (1...lines).map { "Line \($0) of an ordinary document." }
                    .joined(separator: "\n\n")
                controller.loadText(body)
                window.setContentSize(NSSize(width: 900, height: 600))
                controller.view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))

                let text = editor.text as NSString
                let target: Int
                switch where_ {
                case "end": target = text.length
                case "start": target = 0
                default: target = text.range(of: "Line \(max(1, lines / 2))").location
                }
                editor.textView.setSelectedRange(NSRange(location: target, length: 0))
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))

                var offsets: [CGFloat] = []
                for _ in 0..<keys {
                    if deleting {
                        editor.textView.deleteBackward(nil)
                    } else {
                        editor.textView.insertText(
                            newlines ? "\n" : "x", replacementRange: editor.textView.selectedRange())
                    }
                    if settling { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
                    offsets.append(editor.scrollView.contentView.bounds.origin.y)
                }
                var jump: CGFloat = 0
                for i in 1..<max(1, offsets.count) {
                    jump = max(jump, abs(offsets[i] - offsets[i - 1]))
                }
                let clip = editor.scrollView.contentView
                let caret = editor.textView.selectedRange().location
                let rect = editor.textView.lineFragmentRect(atCharacterIndex: caret) ?? .zero
                let gap = rect.midY - (clip.bounds.origin.y + clip.bounds.height / 2)
                return (abs(gap), jump, (offsets.last ?? 0) < 1)
            }

            // A line is about 22 points, so a jump of more than two lines
            // between consecutive keystrokes is the page lurching.
            let lurch: CGFloat = 50

            for (name, at, pastEnd, newlines) in [
                ("typing in the middle", "middle", true, false),
                ("typing in the middle, past-end off", "middle", false, false),
                ("typing at the end", "end", true, false),
                ("typing at the end, past-end off", "end", false, false),
                ("returns at the end", "end", true, true),
                ("returns at the end, past-end off", "end", false, true),
                ("returns in the middle", "middle", true, true),
            ] as [(String, String, Bool, Bool)] {
                let fast = typing(lines: 300, at: at, pastEnd: pastEnd, keys: 20,
                                  newlines: newlines, settling: false)
                check("typewriter: \(name), typed fast, stays on the middle line",
                      fast.offCentre < 2, String(format: "%.0fpt off centre", fast.offCentre))
                check("typewriter: \(name), typed fast, never lurches",
                      fast.jump < lurch, String(format: "biggest jump %.0fpt", fast.jump))

                let slow = typing(lines: 300, at: at, pastEnd: pastEnd, keys: 8,
                                  newlines: newlines, settling: true)
                check("typewriter: \(name), typed slowly, stays on the middle line",
                      slow.offCentre < 2, String(format: "%.0fpt off centre", slow.offCentre))
            }

            let deleted = typing(lines: 300, at: "middle", pastEnd: true, keys: 8,
                                 deleting: true, settling: true)
            check("typewriter: deleting keeps the line on the middle too",
                  deleted.offCentre < 2, String(format: "%.0fpt off centre", deleted.offCentre))

            // The first line cannot be in the middle of the window without
            // scrolling the document off the top, so it correctly is not.
            let atStart = typing(lines: 300, at: "start", pastEnd: true, keys: 8, settling: true)
            check("typewriter: at the top of a document the page stays at the top",
                  atStart.atTop, "it scrolled away from the top")

            // A document shorter than the window cannot scroll at all.
            let tiny = typing(lines: 3, at: "end", pastEnd: true, keys: 8, settling: true)
            check("typewriter: a document shorter than the window does not lurch",
                  tiny.jump < lurch, String(format: "biggest jump %.0fpt", tiny.jump))

            manager.typewriterScrolling = wasTypewriter
            manager.scrollPastEnd = wasPastEnd
            check("typewriter: the checks put the settings back",
                  manager.typewriterScrolling == wasTypewriter
                    && manager.scrollPastEnd == wasPastEnd)
        }

        // --- Focus mode dims what you are not in, and only that ---------------
        // It used to restyle the whole document every time the caret crossed a
        // paragraph, which invalidated the layout: with typewriter scrolling on
        // the page lurched thousands of points mid-sentence. Now only the
        // paragraph being left and the one being entered are touched, so this
        // checks the dimming is still right after moving about.
        do {
            let manager = ThemeManager.shared
            let wasFocus = manager.focusMode
            manager.focusMode = true

            controller.loadText("First paragraph here.\n\nSecond paragraph here.\n\nThird one.\n")
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))

            let editor = controller.editor
            let text = editor.text as NSString

            func ink(_ needle: String) -> NSColor? {
                let at = text.range(of: needle).location
                guard at != NSNotFound else { return nil }
                return editor.textView.textStorage?
                    .attribute(.foregroundColor, at: at, effectiveRange: nil) as? NSColor
            }

            func putCaret(in needle: String) {
                editor.textView.setSelectedRange(
                    NSRange(location: text.range(of: needle).location + 2, length: 0))
                RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            }

            putCaret(in: "First paragraph")
            let firstActive = ink("First paragraph")
            let secondDimmed = ink("Second paragraph")
            check("focus: the paragraph you are in is not dimmed",
                  firstActive != nil && secondDimmed != nil && firstActive != secondDimmed,
                  firstActive == secondDimmed ? "active and dimmed came back the same colour" : "")

            // Moving to another paragraph has to dim the one left behind and
            // brighten the one entered. Restyling only what changed is exactly
            // where that could go wrong.
            putCaret(in: "Second paragraph")
            check("focus: moving on brightens the paragraph entered",
                  ink("Second paragraph") == firstActive,
                  ink("Second paragraph") == firstActive ? "" : "the new paragraph is not at full strength")
            check("focus: and dims the one left behind",
                  ink("First paragraph") == secondDimmed,
                  ink("First paragraph") == secondDimmed ? "" : "the old paragraph stayed bright")

            putCaret(in: "Third one")
            check("focus: a third move still leaves only one bright",
                  ink("Third one") == firstActive
                    && ink("First paragraph") == secondDimmed
                    && ink("Second paragraph") == secondDimmed,
                  ink("Third one") == firstActive ? "" : "more than one paragraph is at full strength")

            manager.focusMode = false
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            controller.loadText("First paragraph here.\n\nSecond paragraph here.\n")
            controller.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            check("focus: turned off, nothing is dimmed",
                  ink("First paragraph") == ink("Second paragraph"),
                  ink("First paragraph") == ink("Second paragraph") ? "" : "something stayed dimmed with focus mode off")

            manager.focusMode = wasFocus
        }

        // --- Features that have to work together ------------------------------
        // Each of these is fine on its own and was not in combination. Its own
        // window and its own editor: sharing the one the rest of the checks use
        // made the numbers move between runs of the same binary, which is a
        // measurement reporting on the checks above it rather than on the app.
        do {
            let manager = ThemeManager.shared
            let wasTypewriter = manager.typewriterScrolling
            let wasFocus = manager.focusMode

            let page = DocumentViewController()
            let stage = OffscreenWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                styleMask: [.titled, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            stage.contentViewController = page
            stage.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            stage.orderFront(nil)
            let editor = page.editor

            let body = (1...80).map { "## Heading \($0)\n\nProse under heading \($0)." }
                .joined(separator: "\n\n")

            func load(height: CGFloat = 600) {
                stage.setContentSize(NSSize(width: 900, height: height))
                page.loadText(body)
                page.view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            }

            // Jumping to a heading from the index, with typewriter mode both
            // ways. Through the animator this depended on an animation actually
            // running, and where one does not the scroll never happened: the
            // click did nothing at all.
            for typewriter in [false, true] {
                manager.typewriterScrolling = typewriter
                manager.focusMode = false
                load()
                let target = (editor.text as NSString).range(of: "## Heading 60").location
                editor.reveal(target)
                RunLoop.current.run(until: Date().addingTimeInterval(0.7))
                let clip = editor.scrollView.contentView
                let rect = editor.textView.lineFragmentRect(atCharacterIndex: target) ?? .zero
                check("index: a heading jumped to lands on screen, typewriter \(typewriter ? "on" : "off")",
                      rect.midY > clip.bounds.minY && rect.midY < clip.bounds.maxY,
                      String(format: "heading at %.0f, window %.0f to %.0f",
                             rect.midY, clip.bounds.minY, clip.bounds.maxY))
            }

            // Resizing moves the middle of the window, and the line typewriter
            // mode holds there has to move with it.
            manager.typewriterScrolling = true
            manager.focusMode = false
            load()
            let middle = (editor.text as NSString).range(of: "## Heading 40").location
            editor.textView.setSelectedRange(NSRange(location: middle, length: 0))
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
            for height in [400.0, 800.0, 500.0] as [CGFloat] {
                stage.setContentSize(NSSize(width: 900, height: height))
                page.view.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                let clip = editor.scrollView.contentView
                let rect = editor.textView.lineFragmentRect(
                    atCharacterIndex: editor.textView.selectedRange().location) ?? .zero
                let gap = abs(rect.midY - (clip.bounds.origin.y + clip.bounds.height / 2))
                check("typewriter: resizing to \(Int(height)) keeps the line on the middle",
                      gap < 2, String(format: "%.0fpt off centre", gap))
            }

            // Focus mode restyled the whole document on every paragraph, which
            // invalidated its layout, so the caret's measured position came back
            // wrong and the page lurched by thousands of points mid-sentence.
            for (focus, typewriter) in [(true, true), (true, false), (false, true), (false, false)] {
                manager.focusMode = focus
                manager.typewriterScrolling = typewriter
                load()
                editor.textView.setSelectedRange(NSRange(location: middle, length: 0))
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                var worst: CGFloat = 0
                var previous = editor.scrollView.contentView.bounds.origin.y
                for _ in 0..<15 {
                    editor.textView.insertText("y", replacementRange: editor.textView.selectedRange())
                    RunLoop.current.run(until: Date().addingTimeInterval(0.04))
                    let now = editor.scrollView.contentView.bounds.origin.y
                    worst = max(worst, abs(now - previous)); previous = now
                }
                check("typing with focus \(focus ? "on " : "off") and typewriter \(typewriter ? "on " : "off") does not lurch",
                      worst < 120, String(format: "biggest jump %.0fpt", worst))
            }

            manager.focusMode = wasFocus
            manager.typewriterScrolling = wasTypewriter
            stage.orderOut(nil)
            check("the combination checks put the settings back",
                  manager.focusMode == wasFocus && manager.typewriterScrolling == wasTypewriter)
        }

        // --- Room at the top, whatever the system is showing ------------------
        // Tabs are the system's now, and a tab bar takes a second band of the
        // window. The page is drawn under a transparent title bar, so the air
        // above the first line was a fixed number, and the first heading ended
        // up behind the tab bar the day tabs were allowed.
        do {
            // 66 is a measured title bar with the empty unified toolbar this
            // app carries; a tab bar adds 28 to it.
            let plain = EditorViewController.topInset(systemChrome: 66, firstLine: 40)
            let tabbed = EditorViewController.topInset(systemChrome: 94, firstLine: 40)
            check("top inset: the air under the title bar is the page's own margin, once",
                  plain - 66 == 40, "\(plain - 66)")
            check("top inset: a tab bar pushes the first line down",
                  tabbed > plain, "\(plain) then \(tabbed)")
            check("top inset: by the height the tab bar actually takes",
                  tabbed - plain == 28, "\(tabbed - plain)")
            check("top inset: a window that reports nothing still has a margin",
                  EditorViewController.topInset(systemChrome: 0, firstLine: 0) == 56,
                  "\(EditorViewController.topInset(systemChrome: 0, firstLine: 0))")
        }

        // --- Annotating a passage ---------------------------------------------
        // MarkViewer keeps annotations in the app. These go in the file, as a
        // highlight and a footnote, so the note is readable in any other editor
        // and shows up in a diff. The arithmetic is checked here; the text view
        // only carries it out.
        do {
            check("annotate: the first note in a document is one",
                  Annotations.nextMarker(in: "Plain prose.\n") == 1)
            check("annotate: numbering continues from what the file uses",
                  Annotations.nextMarker(in: "A[^1] and B[^2]\n\n[^1]: x\n[^2]: y\n") == 3)

            // Numbered from the highest in use, not from how many there are:
            // deleting the middle note must not reissue a marker still in play.
            check("annotate: a deleted note does not get its number reused",
                  Annotations.nextMarker(in: "A[^1] and C[^3]\n\n[^1]: x\n[^3]: z\n") == 4,
                  "\(Annotations.nextMarker(in: "A[^1] and C[^3]\n\n[^1]: x\n[^3]: z\n"))")

            check("annotate: a footnote-looking thing in prose still counts",
                  Annotations.nextMarker(in: "See [^7] somewhere.\n") == 8)

            // Where the definition lands, so notes gather in one block instead
            // of opening a new one each time or piling up blank lines.
            check("annotate: a document with no trailing newline gets a blank line",
                  Annotations.separator(endingIn: "Body.") == "\n\n",
                  Annotations.separator(endingIn: "Body.").debugDescription)
            check("annotate: one trailing newline gets one more",
                  Annotations.separator(endingIn: "Body.\n") == "\n")
            check("annotate: a blank line already there is enough",
                  Annotations.separator(endingIn: "Body.\n\n") == "")
            check("annotate: a second note joins the block above it",
                  Annotations.separator(endingIn: "Body.\n\n[^1]: first\n") == "",
                  Annotations.separator(endingIn: "Body.\n\n[^1]: first\n").debugDescription)
            check("annotate: an empty document needs no separator",
                  Annotations.separator(endingIn: "") == "")

            // And the whole thing through the editor, because the arithmetic
            // being right is not the same as the command working.
            controller.loadText("The rollback plan is the one thing nobody has written.\n")
            controller.view.layoutSubtreeIfNeeded()
            let passage = (controller.editor.text as NSString).range(of: "rollback plan")
            controller.editor.textView.setSelectedRange(passage)
            controller.editor.annotate(nil)
            controller.view.layoutSubtreeIfNeeded()
            let after = controller.editor.text
            check("annotate: the passage is highlighted and marked",
                  after.contains("==rollback plan==[^1]"), after.prefix(60).description)
            check("annotate: the note is defined at the end",
                  after.hasSuffix("[^1]: "), after.suffix(20).debugDescription)
            check("annotate: and the caret is in the note, ready to type",
                  controller.editor.textView.selectedRange().location
                    == (after as NSString).length)

            // A second one on the same document.
            let second = (controller.editor.text as NSString).range(of: "nobody")
            controller.editor.textView.setSelectedRange(second)
            controller.editor.annotate(nil)
            let twice = controller.editor.text
            check("annotate: a second note takes the next number",
                  twice.contains("==nobody==[^2]"), "")
            check("annotate: and joins the block rather than starting another",
                  !twice.contains("\n\n\n"),
                  twice.contains("\n\n\n") ? "it left a run of blank lines" : "")

            // It has to still parse as what it claims to be.
            let parsedNotes = MarkdownParser.parse(twice as NSString)
            check("annotate: what it wrote is still Markdown the app renders",
                  parsedNotes.lines.contains { if case .footnoteDefinition = $0.kind { return true }
                                               return false },
                  parsedNotes.lines.contains { if case .footnoteDefinition = $0.kind { return true }
                                               return false } ? "" : "none was parsed")
        }

        // --- The contents list ------------------------------------------------
        // Headings down the side, so a long document can be moved around in.
        // Off by default: double-clicking a file gets a page and nothing else.
        // The extraction is pure, so the awkward documents are checked here
        // rather than by opening a sidebar and looking at it.
        do {
            func outline(_ text: String) -> [Outline.Entry] {
                Outline.entries(of: MarkdownParser.parse(text as NSString), in: text)
            }

            check("contents: off unless it has been turned on",
                  !ThemeManager.shared.showsContents)

            // It floats beside the page, and only where there is a margin to
            // spare. A narrow window keeps its measure and drops the index,
            // which is what documentation sites do rather than squeeze the text.
            let wide = DocumentViewController.hasRoomForContents(
                pageWidth: 1400, columnWidth: 700)
            let narrow = DocumentViewController.hasRoomForContents(
                pageWidth: 900, columnWidth: 700)
            check("contents: a wide window has room for the index", wide)
            check("contents: a narrow one does not, and keeps its measure", !narrow)
            check("contents: the threshold is the margin, not the window",
                  DocumentViewController.hasRoomForContents(pageWidth: 1200, columnWidth: 300),
                  "a narrow column leaves margin even in a smaller window")
            check("contents: a short document does not get an index",
                  DocumentViewController.contentsMinimum > 3,
                  "\(DocumentViewController.contentsMinimum) headings needed")

            // Opening a document puts you at the top of it, caret included.
            controller.loadText("# One\n\nBody.\n\n## Two\n\nMore body.\n")
            controller.view.layoutSubtreeIfNeeded()
            check("contents: a freshly opened document has the caret at the start",
                  controller.editor.textView.selectedRange().location == 0,
                  "caret at \(controller.editor.textView.selectedRange().location)")

            let simple = outline("# One\n\nBody.\n\n## Two\n\nBody.\n\n### Three\n")
            check("contents: every heading is listed",
                  simple.map(\.title) == ["One", "Two", "Three"],
                  "\(simple.map(\.title))")
            check("contents: nesting is by depth used, not by level",
                  simple.map(\.indent) == [0, 1, 2], "\(simple.map(\.indent))")

            // A document that never uses `#` should not be indented for one.
            let starts = outline("## A\n\nBody.\n\n## B\n\n### C\n")
            check("contents: a document starting at ## is not indented for a # it lacks",
                  starts.map(\.indent) == [0, 0, 1], "\(starts.map(\.indent))")

            // A jump from ## straight to #### is one step in, not two.
            let jump = outline("## A\n\n#### B\n")
            check("contents: a skipped level indents one step",
                  jump.map(\.indent) == [0, 1], "\(jump.map(\.indent))")

            check("contents: a bare marker being typed is not a row",
                  outline("# Real\n\n##\n").map(\.title) == ["Real"],
                  "\(outline("# Real\n\n##\n").map(\.title))")

            check("contents: closed ATX loses its trailing hashes",
                  outline("## Middle ##\n").map(\.title) == ["Middle"],
                  "\(outline("## Middle ##\n").map(\.title))")

            check("contents: setext headings count too",
                  outline("Title\n=====\n\nBody.\n").map(\.title) == ["Title"],
                  "\(outline("Title\n=====\n\nBody.\n").map(\.title))")

            check("contents: a document with no headings lists nothing",
                  outline("Just prose.\n\nMore prose.\n").isEmpty)

            // A `#` inside a fence is code, not a heading.
            let fenced = outline("# Real\n\n```\n# not a heading\n```\n")
            check("contents: a hash inside a code fence is not a heading",
                  fenced.map(\.title) == ["Real"], "\(fenced.map(\.title))")

            // Where the caret is, so the list can light the section being worked
            // on. The last heading at or before it.
            let doc = "# One\n\nBody.\n\n## Two\n\nBody.\n"
            let entries = outline(doc)
            let secondAt = (doc as NSString).range(of: "## Two").location
            check("contents: the caret in the first section lights the first",
                  Outline.entry(at: 3, in: entries)?.title == "One")
            check("contents: and in the second lights the second",
                  Outline.entry(at: secondAt + 2, in: entries)?.title == "Two")
            check("contents: before any heading, nothing is lit",
                  Outline.entry(at: 0, in: outline("Prose first.\n\n# Later\n")) == nil)

            // The cost, because this runs on the same debounce as the word count
            // and a document can be large.
            let long = (1...2000).map { "## Section \($0)\n\nProse.\n" }.joined()
            let parsedLong = MarkdownParser.parse(long as NSString)
            let began = Date()
            let many = Outline.entries(of: parsedLong, in: long)
            let took = Date().timeIntervalSince(began)
            check("contents: two thousand headings are listed",
                  many.count == 2000, "\(many.count)")
            check("contents: and listed quickly enough to sit on the debounce",
                  took < 0.05, String(format: "%.1fms", took * 1000))
        }

        // --- Live mode governs whether anything moves on its own --------------
        // One switch over both directions. On, the page follows the file and the
        // file follows the page. Off, neither moves unless asked, and saving
        // over a file that changed in the meantime has to ask first.
        //
        // Checked by writing to the file from outside and reading what the page
        // did about it, because the whole feature is about what happens when
        // something other than this window writes.
        do {
            let documentController = (NSDocumentController.shared as? KvillDocumentController)
                ?? KvillDocumentController()
            let settled = { RunLoop.current.run(until: Date().addingTimeInterval(0.6)) }
            let manager = ThemeManager.shared
            let was = manager.liveMode

            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("kvill-live-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("Watched.md")
            try? "# Watched\n\noriginal body\n".write(to: file, atomically: true, encoding: .utf8)

            manager.liveMode = true
            var doc: NSDocument?
            documentController.openDocument(withContentsOf: file, display: true) { d, _, _ in
                doc = d
                hide(d)
            }
            settled()

            if let live = doc as? MarkdownDocument {
                try? "# Watched\n\nrewritten by something else\n"
                    .write(to: file, atomically: true, encoding: .utf8)
                settled(); settled()
                check("live mode on: the page follows the file",
                      live.controller?.text.contains("rewritten by something else") == true,
                      live.controller?.text.contains("rewritten") == true ? "followed" : "did not")
                check("live mode on: nothing is left waiting to be asked about",
                      !live.hasChangedOnDisk)

                // Off, the same write must not move the page.
                manager.liveMode = false
                let showing = live.controller?.text ?? ""
                try? "# Watched\n\nrewritten a second time\n"
                    .write(to: file, atomically: true, encoding: .utf8)
                settled(); settled()
                check("live mode off: the page keeps showing what was opened",
                      live.controller?.text == showing,
                      live.controller?.text.contains("second time") == true
                        ? "it moved anyway" : "held")
                check("live mode off: but it knows the file moved",
                      live.hasChangedOnDisk)
                check("live mode off: and it kept what arrived, to show later",
                      live.diskText?.contains("rewritten a second time") == true)

                // Reloading is the way back, and it clears the warning with it.
                live.reloadFromDisk(nil)
                settled()
                check("live mode off: reloading catches the page up",
                      live.controller?.text.contains("rewritten a second time") == true,
                      live.controller?.text.contains("second time") == true ? "caught up" : "did not")
                check("live mode off: and there is nothing left to warn about",
                      !live.hasChangedOnDisk)
            } else {
                check("live mode: a document opened to watch", false)
            }

            documentController.documents.forEach {
                $0.updateChangeCount(.changeCleared)
                $0.close()
            }
            settled()
            manager.liveMode = was
            try? FileManager.default.removeItem(at: folder)
        }

        // --- The changes sheet says what would be lost ------------------------
        // Reached from the overwrite warning, which cannot be opened from here
        // because it is a sheet waiting on a person. What can be checked is the
        // listing it shows, which is the part that would be wrong quietly.
        do {
            let same = ChangesSheet.listing(theirs: "a\nb\n", mine: "a\nb\n").string
            check("changes: identical files say so", same.contains("identical"), same.trimmingCharacters(in: .whitespacesAndNewlines))

            let listing = ChangesSheet.listing(
                theirs: "# Title\n\ntheir new line\n",
                mine: "# Title\n\nmy own line\n").string
            check("changes: it shows what is on disk", listing.contains("their new line"))
            check("changes: and what this window would write", listing.contains("my own line"))
            check("changes: without dragging in the lines that match",
                  !listing.contains("# Title"), "it listed the unchanged heading")
        }

        // --- What something else changed gets marked --------------------------
        // Agents and scripts rewrite these files while the window is open. The
        // page already reloaded silently; now the part that moved is lit for a
        // moment. The diff is pure, so it can be checked properly rather than
        // by looking at a screenshot and hoping.
        do {
            func text(_ new: String, _ ranges: [NSRange]) -> [String] {
                let s = new as NSString
                return ranges.map { s.substring(with: $0) }
            }

            check("diff: an unchanged file has nothing to mark",
                  ChangeDiff.changedRanges(from: "a\nb\nc\n", to: "a\nb\nc\n").isEmpty)

            let edited = ChangeDiff.changedRanges(from: "a\nb\nc\n", to: "a\nB\nc\n")
            check("diff: one changed line marks that line",
                  text("a\nB\nc\n", edited) == ["B"], "\(text("a\nB\nc\n", edited))")

            // The case the whole thing is for: an agent rewrites a few words in
            // the middle of a long line and the rest of it should stay dark.
            let old = "The quick brown fox jumps over the lazy dog"
            let new = "The quick purple fox jumps over the lazy dog"
            let words = ChangeDiff.changedRanges(from: old, to: new)
            check("diff: a reworded line marks only the words that changed",
                  text(new, words) == ["purple"], "\(text(new, words))")

            let added = ChangeDiff.changedRanges(from: "a\nb\n", to: "a\nNEW\nb\n")
            check("diff: an inserted line marks the insertion, not the rest",
                  text("a\nNEW\nb\n", added) == ["NEW"], "\(text("a\nNEW\nb\n", added))")

            // An insert in the middle used to drag everything below it into the
            // answer, because the lines after it had all moved along by one.
            let long = (1...12).map { "line \($0)" }.joined(separator: "\n")
            let spliced = long.replacingOccurrences(of: "line 6", with: "line 6\ninserted")
            let splice = ChangeDiff.changedRanges(from: long, to: spliced)
            check("diff: everything below an insert is not counted as changed",
                  text(spliced, splice) == ["inserted"], "\(text(spliced, splice))")

            let two = ChangeDiff.changedRanges(from: "a\nb\nc\nd\n", to: "a\nB\nc\nD\n")
            check("diff: two separate edits are two marks",
                  text("a\nB\nc\nD\n", two) == ["B", "D"], "\(text("a\nB\nc\nD\n", two))")

            let block = ChangeDiff.changedRanges(from: "a\nb\nc\nd\n", to: "a\nB\nC\nd\n")
            check("diff: adjacent changed lines join into one mark",
                  block.count == 1, "\(block.count) marks")

            let deleted = ChangeDiff.changedRanges(from: "a\nb\nc\n", to: "a\nc\n")
            check("diff: a pure deletion still marks where it went",
                  deleted.count == 1 && deleted[0].length == 0,
                  "\(deleted.count) marks, length \(deleted.first?.length ?? -1)")

            // A whole file replaced is the case that would otherwise sit there
            // multiplying one side by the other.
            let big = (1...4000).map { "line \($0)" }.joined(separator: "\n")
            let other = (1...4000).map { "other \($0)" }.joined(separator: "\n")
            let started = Date()
            let wholesale = ChangeDiff.changedRanges(from: big, to: other)
            let took = Date().timeIntervalSince(started)
            check("diff: a wholesale rewrite is answered at all",
                  !wholesale.isEmpty, "\(wholesale.count) marks")
            check("diff: and answered quickly, not by multiplying it out",
                  took < 0.2, String(format: "%.0fms", took * 1000))

            // The same size, but a single edit inside it: the ends are trimmed
            // first, so this stays precise however long the file is.
            var oneEdit = (1...4000).map { "line \($0)" }
            oneEdit[2000] = "line 2001 changed by something else"
            let precise = ChangeDiff.changedRanges(
                from: big, to: oneEdit.joined(separator: "\n"))
            check("diff: one edit in a long file is still one mark",
                  precise.count == 1, "\(precise.count) marks")

            // And the fade, which is a clock rather than a diff.
            let flashView = controller.editor.textView
            controller.loadText("alpha\nbeta\ngamma\n")
            controller.view.layoutSubtreeIfNeeded()
            flashView.flashChanges([NSRange(location: 6, length: 4)])
            check("flash: a change starts fully lit",
                  flashView.flashStrength == 1, "\(flashView.flashStrength)")
            check("flash: and knows what it is lighting",
                  flashView.flashRangesForTest.count == 1)
            RunLoop.current.run(
                until: Date().addingTimeInterval(
                    EditorTextView.flashHold + EditorTextView.flashFade + 0.3))
            check("flash: and it is gone afterwards, leaving nothing lit",
                  flashView.flashStrength == 0 && flashView.flashRangesForTest.isEmpty,
                  "\(flashView.flashRangesForTest.count) still lit")
        }

        // --- The lit row is the file the window is showing --------------------
        // Two windows on the same folder. Clicking a file that is already open
        // in the other window raises that window and leaves this one alone,
        // which is right, but the row was lit from what had been clicked rather
        // than from what this window ended up showing. It said this window was
        // showing a file that was in fact on the other screen.
        do {
            let documentController = (NSDocumentController.shared as? KvillDocumentController)
                ?? KvillDocumentController()
            let settled = { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("kvill-twowindows-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let one = folder.appendingPathComponent("One.md")
            let two = folder.appendingPathComponent("Two.md")
            try? "# One\n".write(to: one, atomically: true, encoding: .utf8)
            try? "# Two\n".write(to: two, atomically: true, encoding: .utf8)

            var first: NSDocument?
            var second: NSDocument?
            documentController.openDocument(withContentsOf: one, display: true) { d, _, _ in first = d }
            settled()
            documentController.openDocument(withContentsOf: two, display: true) { d, _, _ in second = d }
            settled()

            // Ordering these out would turn the case being checked into the
            // other branch: openInPlace only raises the other window when that
            // window is visible. So they stay visible to AppKit and invisible to
            // whoever is sitting in front of the machine, which is the only way
            // to have both. Ordering them out was tried and quietly checked
            // nothing; leaving them up put two windows in someone's face.
            for document in [first, second] {
                guard let window = document?.windowControllers.first?.window else { continue }
                window.alphaValue = 0
                window.ignoresMouseEvents = true
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            }
            let splitOne = first?.windowControllers.first?.window?.contentViewController
                as? DocumentSplitViewController
            let splitTwo = second?.windowControllers.first?.window?.contentViewController
                as? DocumentSplitViewController
            if let splitOne, let splitTwo {
                splitOne.showFolder(folder)
                splitTwo.showFolder(folder)
                settled()
                check("two windows: the other window counts as on screen",
                      first?.windowControllers.first?.window?.isVisible == true,
                      "otherwise this is checking the wrong branch")
                check("two windows: and neither can actually be seen",
                      [first, second].allSatisfy {
                          ($0?.windowControllers.first?.window?.alphaValue ?? 1) == 0
                      })
                check("two windows: each starts on its own file",
                      splitTwo.sidebar.tree.selectedURL?.lastPathComponent == "Two.md",
                      splitTwo.sidebar.tree.selectedURL?.lastPathComponent ?? "nothing")

                // The click that caused it: One.md is open in the other window.
                splitTwo.openFromSidebarForTest(one)
                settled()
                check("two windows: the second window still shows its own file",
                      splitTwo.page.documentURL?.lastPathComponent == "Two.md",
                      splitTwo.page.documentURL?.lastPathComponent ?? "nothing")
                check("two windows: and its lit row still says so",
                      splitTwo.sidebar.tree.selectedURL?.lastPathComponent == "Two.md",
                      splitTwo.sidebar.tree.selectedURL?.lastPathComponent ?? "nothing")
                check("two windows: the row matches the page, whatever it is",
                      splitTwo.sidebar.tree.selectedURL?.standardizedFileURL
                        == splitTwo.page.documentURL?.standardizedFileURL)
            } else {
                check("two windows: both windows hold a split view", false)
            }

            documentController.documents.forEach { hide($0) }
            documentController.documents.forEach {
                $0.updateChangeCount(.changeCleared)
                $0.close()
            }
            settled()
            try? FileManager.default.removeItem(at: folder)
        }

        // --- Autosave is a setting, and turning it off keeps the work ---------
        // Off, Kvill is an ordinary Cmd-S editor. The dangerous part is not the
        // toggle, it is what the rest of the app assumed while it was always on:
        // switching files in the sidebar ends in `autosave` and then `close`,
        // and with autosave off the first writes nothing and the second closes
        // without asking. Clicking through a folder would have dropped every
        // edit on the way past.
        do {
            let documentController = (NSDocumentController.shared as? KvillDocumentController)
                ?? KvillDocumentController()
            let settled = { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
            let manager = ThemeManager.shared
            let wasAutosaving = manager.liveMode

            check("live mode: on unless it has been turned off", wasAutosaving)
            check("live mode: the document class asks the setting",
                  MarkdownDocument.autosavesInPlace)
            manager.liveMode = false
            check("live mode: turning it off reaches NSDocument",
                  !MarkdownDocument.autosavesInPlace)

            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("kvill-autosave-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let one = folder.appendingPathComponent("One.md")
            let two = folder.appendingPathComponent("Two.md")
            try? "# One\n".write(to: one, atomically: true, encoding: .utf8)
            try? "# Two\n".write(to: two, atomically: true, encoding: .utf8)

            var opened: NSDocument?
            documentController.openDocument(withContentsOf: one, display: true) { d, _, _ in
                opened = d
                hide(d)
            }
            settled()
            if let first = opened, let host = first.windowControllers.first?.window {
                (host.contentViewController as? DocumentSplitViewController)?.page
                    .editor.textView.insertText(
                        "UNSAVED-WORK\n", replacementRange: NSRange(location: 0, length: 0))
                first.updateChangeCount(.changeDone)
                settled()

                let reused = documentController.openInPlace(two, replacing: first)
                settled()
                check("live mode off: an edited file does not give up its window",
                      !reused)
                check("live mode off: and it is still open with its edit",
                      documentController.documents.contains { $0 === first }
                        && first.isDocumentEdited)

                // The same click with autosave on is the normal path, and has to
                // keep working: this is the only thing stopping a folder full of
                // notes opening a window each.
                manager.liveMode = true
                first.updateChangeCount(.changeCleared)
                settled()
                check("live mode on: the window is handed over as before",
                      documentController.openInPlace(two, replacing: first))
                settled()
            } else {
                check("autosave: a document opened to edit", false)
            }

            documentController.documents.forEach {
                $0.updateChangeCount(.changeCleared)
                $0.close()
            }
            settled()
            manager.liveMode = wasAutosaving
            check("live mode: the checks put the setting back", manager.liveMode)
            try? FileManager.default.removeItem(at: folder)
        }

        // --- A launch that opens a file leaves no blank window behind ---------
        // Double-clicking a file in the Finder put up two windows stacked
        // exactly on top of each other, an empty one and the file. AppKit asks
        // whether the launch wants an untitled document before it delivers the
        // Apple Event carrying the file, so the launch really does look empty at
        // the moment the question is asked.
        //
        // The launch itself cannot be staged from inside the running app, so
        // what is checked here is the part that can be: the blank document is
        // marked as the launch's own, and a file opening behind it takes it
        // away. The real sequence was reproduced against /Applications/Kvill.app
        // by hand, with the app not running and no saved state, and both windows
        // came up at 414,105.
        do {
            let documentController = (NSDocumentController.shared as? KvillDocumentController)
                ?? KvillDocumentController()
            let settled = { RunLoop.current.run(until: Date().addingTimeInterval(0.4)) }
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("kvill-launch-\(ProcessInfo.processInfo.processIdentifier)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appendingPathComponent("Opened.md")
            try? "# Opened\n".write(to: file, atomically: true, encoding: .utf8)

            // Exactly what the delegate does when AppKit asks at launch.
            documentController.isMakingLaunchPlaceholder = true
            let blank = try? documentController.openUntitledDocumentAndDisplay(true)
            hide(blank)
            settled()
            check("launch: the blank document is recognised as the launch's own",
                  documentController.hasLaunchPlaceholder)

            documentController.openDocument(withContentsOf: file, display: true) { d, _, _ in
                hide(d)
            }
            settled()
            check("launch: opening a file closes the blank window",
                  !documentController.hasLaunchPlaceholder)
            let untitled = documentController.documents.filter { $0.fileURL == nil }
            check("launch: no untitled document is left standing",
                  untitled.isEmpty, "\(untitled.count)")

            // The window the launch put up is the one a folder drop moves into,
            // and closing it as a stray took it out from under the document
            // arriving in it. Dropping a folder within two seconds of opening
            // the app closed the window and left nothing at all on screen.
            documentController.documents.forEach { $0.close() }
            settled()
            documentController.isMakingLaunchPlaceholder = true
            let reused = try? documentController.openUntitledDocumentAndDisplay(true)
            hide(reused)
            settled()
            if let reused, let host = reused.windowControllers.first?.window {
                let moved = documentController.openInPlace(file, replacing: reused)
                settled()
                check("launch: a folder dropped into the blank window is taken by it",
                      moved)
                let stillThere = documentController.documents
                    .contains { $0.windowControllers.first?.window === host }
                check("launch: and the window is still there afterwards", stillThere)
                check("launch: showing the file rather than nothing",
                      documentController.document(for: host)?.fileURL?.lastPathComponent
                        == "Opened.md",
                      documentController.document(for: host)?
                        .fileURL?.lastPathComponent ?? "nothing")
            } else {
                check("launch: a blank window was opened to drop into", false)
            }

            // The other half: a blank window someone has typed into is theirs,
            // and opening a file must not take it away.
            documentController.documents.forEach { $0.close() }
            settled()
            documentController.isMakingLaunchPlaceholder = true
            let typedIn = try? documentController.openUntitledDocumentAndDisplay(true)
            hide(typedIn)
            typedIn?.updateChangeCount(.changeDone)
            settled()
            documentController.openDocument(withContentsOf: file, display: true) { d, _, _ in
                hide(d)
            }
            settled()
            check("launch: a blank window that was typed into is left alone",
                  documentController.documents.contains { $0.fileURL == nil })

            documentController.documents.forEach {
                $0.updateChangeCount(.changeCleared)
                $0.close()
            }
            settled()
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

            // No hairline under the title bar, from either pane. Checked again
            // after a file switch, because the page pane used to be built twice
            // and the second one came without it: the line appeared the moment
            // anyone clicked a row in the sidebar and stayed for the rest of
            // that window's life. In full screen it is the border across the
            // strip that slides down from the top edge.
            check("sidebar: no pane draws a hairline under the title bar",
                  !split.drawsTitlebarSeparator)
            split.showPage(DocumentViewController())
            check("sidebar: and still none after switching files",
                  !split.drawsTitlebarSeparator)

            host.close()
            try? FileManager.default.removeItem(at: folder)
        }

        // Nothing this run opened may still be on screen. A check that leaves a
        // window behind is a check that changed the machine it ran on.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let leftBehind = NSApp.windows.filter {
            $0.isVisible && $0.frame.origin.x > -10000 && $0.alphaValue > 0
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

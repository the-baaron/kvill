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

        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            let mark = passed ? "ok  " : "FAIL"
            if !passed { failures += 1 }
            print("\(mark) \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        }

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

        // --- Scroll edge effects --------------------------------------------
        let edges = controller.view.subviews.compactMap { $0 as? ScrollEdgeEffectView }
        check("scroll edge views present", edges.count == 2, "\(edges.count) found")
        check("scroll edges visible", edges.allSatisfy { !$0.isHidden && $0.alphaValue > 0.3 },
              edges.map { "alpha \(String(format: "%.2f", $0.alphaValue))" }.joined(separator: ", "))
        check("scroll edges have height", edges.allSatisfy { $0.frame.height > 30 },
              edges.map { "h \(Int($0.frame.height))" }.joined(separator: ", "))
        check("progressive blur mask built", edges.allSatisfy { $0.hasMask },
              edges.map { $0.hasMask ? "masked" : "no mask" }.joined(separator: ", "))

        // --- Chrome ----------------------------------------------------------
        let dragAreas = controller.view.subviews.compactMap { $0 as? WindowDragArea }
        check("window drag strip present", dragAreas.count == 1)
        check("drag strip moves the window", dragAreas.first?.mouseDownCanMoveWindow == true)

        let bars = controller.view.subviews.compactMap { $0 as? DisplayOptionsBar }
        check("display options bar present", bars.count == 1)

        // --- Palette popover contents ----------------------------------------
        for section in OptionsPalette.Section.allCases {
            let palette = OptionsPalette(section: section)
            let built = palette.view.subviews.first?.subviews.count ?? 0
            check("palette builds: \(section.title)", built > 0, "\(built) rows")
        }

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}

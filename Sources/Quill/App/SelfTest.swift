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

        // --- Scroll edge blur -------------------------------------------------
        // Proved by pixels: render a strip of the document, blur it, and confirm
        // the result actually differs from the unblurred original.
        let textView = controller.editor.textView
        let size = NSSize(width: 700, height: 90)

        for (name, edge) in [("top", ScrollEdgeView.Edge.top), ("bottom", .bottom)] {
            let probe = ScrollEdgeView(edge: edge, theme: ThemeManager.shared.theme)
            probe.source = textView
            guard let rendered = probe.renderForTest(size: size) else {
                check("edge renders: \(name)", false, "no bitmap")
                continue
            }
            // NSBitmapImageRep indexes from the top-left, so row 0 is the top.
            let rows = rendered.pixelsHigh
            let band = rows / 4
            let visualTop = ScrollEdgeRenderer.darkness(rendered, rows: 0..<band)
            let visualBottom = ScrollEdgeRenderer.darkness(rendered, rows: (rows - band)..<rows)

            check("edge renders: \(name)", visualTop + visualBottom > 0.0005,
                  "top \(String(format: "%.4f", visualTop)) bottom \(String(format: "%.4f", visualBottom))")
            // The covered end is the window edge: page colour hides the ink there.
            let correct = edge == .top ? visualTop < visualBottom : visualBottom < visualTop
            check("edge fades the right way: \(name)", correct,
                  "top \(String(format: "%.4f", visualTop)) vs bottom \(String(format: "%.4f", visualBottom))")

            // Is the content actually blurred? Compare how sharp it is against
            // the same strip drawn straight, in the band nearest the edge where
            // the blur is strongest. Fading is switched off so the measurement
            // is of blur and not of paint over the top of it.
            let strip = NSRect(x: 0, y: 200, width: size.width, height: size.height)
            guard let straight = ScrollEdgeRenderer.renderStrip(strip: strip, scale: 2, render: {
                      textView.renderPage($0)
                  }),
                  let softened = probe.renderForTest(size: size, fade: false) else {
                check("edge blurs: \(name)", false, "no bitmap")
                continue
            }
            let rowsHigh = straight.pixelsHigh
            let edgeBand = edge == .top ? 0..<(rowsHigh / 3) : (rowsHigh * 2 / 3)..<rowsHigh
            let before = ScrollEdgeRenderer.sharpness(straight, rows: edgeBand)
            let after = ScrollEdgeRenderer.sharpness(softened, rows: edgeBand)
            check("edge blurs: \(name)", before > 0 && after < before * 0.7,
                  "sharpness \(String(format: "%.4f", before)) to \(String(format: "%.4f", after))")
        }

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

        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        return failures == 0 ? 0 : 1
    }
}

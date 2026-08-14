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

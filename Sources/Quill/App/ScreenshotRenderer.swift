import AppKit

/// Renders a Markdown file to a PNG without showing a window.
///
/// This exists so the README images can be regenerated from the real editor
/// rather than mocked up, and so layout can be checked in a headless session.
///
///     Quill --render input.md output.png [--theme ink] [--typography editorial]
///           [--size medium] [--width normal] [--panel] [--geometry 900x720]
enum ScreenshotRenderer {

    struct Request {
        var input: String
        var output: String
        var theme: String?
        var typography: String?
        var size: String?
        var width: String?
        var showPanel = false
        var canvas = NSSize(width: 900, height: 760)
        var scale: CGFloat = 2
        /// How far down the document to start drawing, in points.
        var offset: CGFloat = 0
    }

    /// Parses `--render` out of the argument list, returning nil for a normal launch.
    static func parse(_ arguments: [String]) -> Request? {
        guard let index = arguments.firstIndex(of: "--render"),
              arguments.count > index + 2 else { return nil }

        var request = Request(input: arguments[index + 1], output: arguments[index + 2])

        func value(after flag: String) -> String? {
            guard let position = arguments.firstIndex(of: flag),
                  arguments.count > position + 1 else { return nil }
            return arguments[position + 1]
        }

        request.theme = value(after: "--theme")
        request.typography = value(after: "--typography")
        request.size = value(after: "--size")
        request.width = value(after: "--width")
        request.showPanel = arguments.contains("--panel")

        if let geometry = value(after: "--geometry") {
            let parts = geometry.lowercased().split(separator: "x").compactMap { Double($0) }
            if parts.count == 2 {
                request.canvas = NSSize(width: parts[0], height: parts[1])
            }
        }
        if let scale = value(after: "--scale"), let number = Double(scale) {
            request.scale = CGFloat(number)
        }
        if let offset = value(after: "--offset"), let number = Double(offset) {
            request.offset = CGFloat(number)
        }
        return request
    }

    /// Runs the render and returns a process exit code.
    static func run(_ request: Request) -> Int32 {
        let manager = ThemeManager.shared
        if let theme = request.theme {
            guard Palettes.theme(id: theme) != nil else {
                FileHandle.standardError.write(Data("Unknown theme: \(theme)\n".utf8))
                return 2
            }
            manager.selectPalette(id: theme)
        }
        if let typography = request.typography {
            guard TypographyPreset.preset(id: typography) != nil else {
                FileHandle.standardError.write(Data("Unknown typography: \(typography)\n".utf8))
                return 2
            }
            manager.presetID = typography
        }
        if let size = request.size, let value = TextSize(rawValue: size) {
            manager.textSize = value
        }
        if let width = request.width, let value = LineWidth(rawValue: width) {
            manager.lineWidth = value
        }

        let text: String
        do {
            text = try String(contentsOfFile: request.input, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(
                Data("Could not read \(request.input): \(error.localizedDescription)\n".utf8))
            return 1
        }

        let controller = DocumentViewController()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: request.canvas),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.contentViewController = controller
        // Assigning a content view controller resizes the window to that view's
        // fitting size, which is zero here, so the size is set again afterwards.
        window.setContentSize(request.canvas)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = manager.theme.colors.background
        window.appearance = manager.theme.colors.appearance

        // The window must be ordered in for text layout to run, but placing it
        // far off the visible desktop keeps it from flashing on screen.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)

        controller.loadText(text)
        if request.showPanel {
            controller.toggleThemePanel(nil)
        }

        // Let AppKit settle: layout, glyph generation, then a run loop turn so the
        // glass and any animations reach their final state.
        controller.view.layoutSubtreeIfNeeded()
        let textView = controller.editor.textView
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        controller.view.layoutSubtreeIfNeeded()

        // Loading text leaves the caret at the end, and AppKit scrolls to it.
        // Put both back to the top so `--offset` is measured from the start of
        // the document rather than from wherever the view happened to land.
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        controller.editor.scrollView.contentView.setBoundsOrigin(.zero)
        controller.editor.scrollView.reflectScrolledClipView(
            controller.editor.scrollView.contentView)
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }

        guard let representation = renderPage(
            controller.editor.textView,
            size: request.canvas,
            scale: request.scale,
            offset: request.offset,
            theme: manager.theme
        ) else {
            FileHandle.standardError.write(Data("Could not draw the page.\n".utf8))
            return 1
        }
        guard let data = representation.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("Could not encode PNG.\n".utf8))
            return 1
        }
        do {
            try data.write(to: URL(fileURLWithPath: request.output))
        } catch {
            FileHandle.standardError.write(
                Data("Could not write \(request.output): \(error.localizedDescription)\n".utf8))
            return 1
        }

        print("Rendered \(request.output)")
        return 0
    }

    /// Draws the editor page straight into a bitmap.
    ///
    /// Capturing the window is not an option here: the floating chrome is built
    /// from glass and visual-effect views, which force the whole hierarchy to be
    /// layer-backed, and an off-screen layer-backed window never runs a display
    /// pass, so both `cacheDisplay` and `CALayer.render(in:)` come back empty.
    /// Calling the text view's own draw method with a prepared context sidesteps
    /// all of that. The trade-off is that the floating chrome is not in the
    /// image; the page itself, which is what these images are for, is exact.
    private static func renderPage(
        _ textView: EditorTextView, size: NSSize, scale: CGFloat, offset: CGFloat, theme: Theme
    ) -> NSBitmapImageRep? {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        representation.size = size

        guard let base = NSGraphicsContext(bitmapImageRep: representation) else { return nil }
        let cgContext = base.cgContext

        // The text view is flipped, so the context has to be flipped both in its
        // transform and in what AppKit believes about it. Mirroring the transform
        // alone lays the lines out bottom-up; telling AppKit alone mirrors the
        // glyphs. Both together give a correct page.
        cgContext.scaleBy(x: scale, y: scale)
        cgContext.translateBy(x: 0, y: size.height)
        cgContext.scaleBy(x: 1, y: -1)

        let context = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context

        theme.colors.background.setFill()
        NSRect(origin: .zero, size: size).fill()

        cgContext.translateBy(x: 0, y: -offset)
        textView.renderPage(NSRect(x: 0, y: offset, width: size.width, height: size.height))
        return representation
    }
}

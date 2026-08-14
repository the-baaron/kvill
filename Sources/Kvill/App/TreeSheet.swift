import AppKit

/// Draws the file tree offscreen, so the sidebar can be looked at.
///
/// Capturing it is not an option. A source-list outline view forces the window
/// to be layer-backed, an off-screen layer-backed window never runs a display
/// pass, and `cacheDisplay` then returns a blank rectangle that looks exactly
/// like an empty sidebar. The same trap is documented in `ScreenshotRenderer`.
/// So the views are asked to draw themselves, one by one, into a prepared
/// context, which is what the specimen sheet does for the picker buttons.
enum TreeSheet {

    static func render(_ folder: URL, to path: String, theme: String?,
                       size: NSSize = NSSize(width: 240, height: 300)) -> Int32 {
        let manager = ThemeManager.shared
        let saved = manager.settingsSnapshot
        defer { manager.restore(saved) }
        if let theme {
            guard Palettes.theme(id: theme) != nil else {
                FileHandle.standardError.write(Data("Unknown theme: \(theme)\n".utf8))
                return 2
            }
            manager.selectPalette(id: theme)
        }

        let tree = FileTreeView(frame: NSRect(origin: .zero, size: size))
        tree.translatesAutoresizingMaskIntoConstraints = true
        tree.frame = NSRect(origin: .zero, size: size)

        // An outline view lays out only inside a window. The window is never
        // ordered in, so nothing appears on screen.
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        // Without this the sidebar draws in the machine's appearance rather than
        // the theme's, which once produced white text on a white page and looked
        // like a bug in the app instead of a bug in the render.
        window.appearance = ThemeManager.shared.theme.colors.appearance
        window.contentView?.addSubview(tree)
        tree.show(folder)
        tree.layoutSubtreeIfNeeded()
        tree.prepareForRender()

        let scale: CGFloat = 3
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return 1 }
        rep.size = size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return 1 }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        ThemeManager.shared.theme.colors.background.setFill()
        NSRect(origin: .zero, size: size).fill()
        // System-drawn parts, the disclosure triangle and the symbol icons,
        // resolve their colour against the *current drawing* appearance, which
        // outside a real display pass is the machine's rather than the window's.
        // Without this they came out white on a white page.
        let appearance = ThemeManager.shared.theme.colors.appearance ?? NSAppearance.currentDrawing()
        appearance.performAsCurrentDrawingAppearance {
            draw(tree, root: tree, cgContext: context.cgContext)
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
        return 0
    }

    /// Draws a view and everything under it, each in its own coordinate space.
    private static func draw(_ view: NSView, root: NSView, cgContext: CGContext) {
        guard !view.isHidden, view.alphaValue > 0 else { return }

        let rect = view.convert(view.bounds, to: root)
        cgContext.saveGState()
        if view.isFlipped {
            // A flipped view draws from its top edge downwards, so the context
            // has to be mirrored and AppKit has to be told that it is.
            cgContext.translateBy(x: rect.minX, y: rect.maxY)
            cgContext.scaleBy(x: 1, y: -1)
        } else {
            cgContext.translateBy(x: rect.minX, y: rect.minY)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: view.isFlipped)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        cgContext.restoreGState()

        for subview in view.subviews { draw(subview, root: root, cgContext: cgContext) }
    }
}

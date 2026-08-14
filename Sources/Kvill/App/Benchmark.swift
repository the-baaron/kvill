import AppKit

/// Phase timings for opening a document.
///
///     Kvill --benchmark file.md
///
/// Startup is the thing this app is judged on, so it is measured rather than
/// guessed at: process start to ready, then read, parse, style and layout.
enum Benchmark {

    static func run(path: String) -> Int32 {
        let processStart = ProcessInfo.processInfo.systemUptime

        func stamp() -> Double { ProcessInfo.processInfo.systemUptime }
        func ms(_ from: Double, _ to: Double) -> String {
            String(format: "%7.1f ms", (to - from) * 1000)
        }

        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("Could not read \(path)\n".utf8))
            return 1
        }
        let afterRead = stamp()

        // Opening a file pads any table in it, so the cost belongs on the clock.
        let normalizeStart = stamp()
        _ = TableFormatter.normalized(text)
        let afterNormalize = stamp()

        let beforeTheme = stamp()
        _ = ThemeManager.shared.theme.body
        let afterTheme = stamp()

        let afterEditor = stamp()

        let controller = DocumentViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        let beforeContent = stamp()
        window.contentViewController = controller
        let afterContent = stamp()
        window.setContentSize(NSSize(width: 900, height: 700))
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFront(nil)
        let afterWindow = stamp()

        // Parse alone, so it can be separated from applying attributes.
        let nsText = text as NSString
        let parseStart = stamp()
        let parsed = MarkdownParser.parse(nsText)
        let afterParse = stamp()

        controller.documentURL = URL(fileURLWithPath: path)
        controller.loadText(text)
        let afterStyle = stamp()

        let textView = controller.editor.textView
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            // Only the first screenful matters for the window appearing.
            _ = layoutManager.glyphRange(
                forBoundingRect: NSRect(x: 0, y: 0, width: 900, height: 700), in: container)
        }
        let afterFirstScreen = stamp()

        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        let afterFullLayout = stamp()

        // What the machine actually spends its day doing: one keystroke, over
        // and over, in the middle of the document.
        let typingStart = stamp()
        let caret = nsText.length / 2
        controller.editor.textView.setSelectedRange(NSRange(location: caret, length: 0))
        for _ in 0..<50 {
            let at = controller.editor.textView.selectedRange()
            controller.editor.textView.insertText("x", replacementRange: at)
        }
        controller.view.layoutSubtreeIfNeeded()
        let afterTyping = stamp()

        print("""
            document      \(nsText.length) characters, \(parsed.lines.count) lines
            read          \(ms(processStart, afterRead))   (includes process start)
            pad tables    \(ms(normalizeStart, afterNormalize))
            theme + fonts \(ms(beforeTheme, afterTheme))
            window alloc  \(ms(afterTheme, beforeContent))
            content vc    \(ms(beforeContent, afterContent))
            order front   \(ms(afterContent, afterWindow))
            parse         \(ms(parseStart, afterParse))
            load + style  \(ms(afterParse, afterStyle))
            first screen  \(ms(afterStyle, afterFirstScreen))
            full layout   \(ms(afterFirstScreen, afterFullLayout))
            per keystroke \(ms(typingStart, afterTyping)) over 50
            ---
            to first screen \(ms(processStart, afterFirstScreen))
            total           \(ms(processStart, afterFullLayout))
            """)
        return 0
    }
}

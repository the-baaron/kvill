import AppKit

/// Runs the app through a demonstration for a screen recording, from inside.
///
/// The usual way to record a demo is to synthesise keystrokes, which needs
/// Accessibility: a per-app permission a script cannot grant itself, and which
/// took three attempts and still was not in effect. Nothing here is synthesised.
/// The demo calls the same methods the keyboard reaches, so the recording is the
/// app doing the work rather than a puppet of it: text goes in through
/// `insertText`, which is what makes the insert menu appear, Return goes through
/// `doCommand(by:)`, which is how the menu receives it, and the palette and text
/// size go through the same ThemeManager the menu items call.
///
/// It is off unless a launch asks for it, so a demo cannot be left armed on
/// someone's machine.
enum DemoDriver {

    /// Starts the demo if this launch asked for one:
    ///
    ///     open -a Kvill.app document.md --args --demo
    ///
    /// A launch argument rather than a preference. A preference would outlive
    /// the launch that wanted it, needs clearing again afterwards, and goes
    /// through `cfprefsd`, which wedged and hung every `defaults write` while
    /// this was being built. An argument is gone the moment the app quits.
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--demo") else { return }
        run()
    }

    // MARK: - The sequence

    private static func run() {
        // The window puts itself where a recording wants it. Moving another
        // app's window needs Accessibility; moving your own does not.
        after(1.0) { placeWindow() }

        // macOS restores where the caret was left, so without this the video
        // opens on the bottom of the document from the last run.
        after(0.4) {
            textView()?.moveToBeginningOfDocument(nil)
            textView()?.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }

        // A pause: the window is still arriving, and a recording wants a moment
        // of the finished page before anything moves.
        after(2.0) {}

        // 1. The caret walks down the opening lines. Each line reveals its own
        //    syntax in the margin as the caret enters it, which is the single
        //    idea the whole editor is built around.
        for _ in 0..<9 {
            after(0.65) { textView()?.moveDown(nil) }
        }
        after(1.2) {}

        // 2. Typing, at the end of the document, so the recording shows editing
        //    rather than a document someone else already wrote.
        after(0.8) { textView()?.moveToEndOfDocument(nil) }
        after(0.8) { insert("\n\n") }
        type("## Written while recording")
        after(0.5) { insert("\n\n") }
        type("Every character here went in through the editor itself.")
        after(1.0) {}

        // 3. The insert menu. The slash opens it, the word narrows it, Return
        //    takes the selection, all through the paths a person's keys take.
        after(0.8) { insert("\n\n") }
        after(0.6) { insert("/") }
        after(1.4) {}
        type("table", gap: 0.12)
        after(1.6) { textView()?.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
        after(2.0) {}

        // 4. Appearance, app-wide and remembered, as the menu items set it.
        after(1.0) { ThemeManager.shared.cyclePalette() }
        after(1.8) { ThemeManager.shared.cyclePalette() }
        after(1.8) { ThemeManager.shared.stepTextSize(by: 1) }
        after(1.8) {}

        // 5. The document has been saving itself throughout; this is what the
        //    app says when you ask it to save anyway.
        after(1.0) { controller()?.confirmSaved() }
        after(3.0) {}

        // 6. Every piece of interface out of the way, and back.
        after(0.8) { controller()?.toggleInterface(nil) }
        after(2.5) { controller()?.toggleInterface(nil) }
        after(1.5) {}
    }

    // MARK: - Driving

    private static func controller() -> DocumentViewController? {
        let windows = [NSApp.keyWindow, NSApp.mainWindow] + NSApp.windows
        for window in windows.compactMap({ $0 }) {
            if let found = window.contentViewController as? DocumentViewController { return found }
        }
        return nil
    }

    private static func textView() -> EditorTextView? { controller()?.editor.textView }

    /// Centres the window at a size that fills most of the frame, so the
    /// recording is of the app rather than of a desktop with the app on it.
    ///
    /// On the primary display, not on whichever display the window happened to
    /// open on. `screencapture` records the primary one, and a first take was
    /// 75 seconds of an empty desktop because the app had opened on the other
    /// monitor. The primary display is the one whose frame starts at the origin.
    private static func placeWindow() {
        guard let window = controller()?.view.window,
              let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
                ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = NSSize(width: visible.width * 0.94, height: visible.height * 0.95)
        window.setFrame(
            NSRect(x: visible.midX - size.width / 2,
                   y: visible.midY - size.height / 2,
                   width: size.width, height: size.height),
            display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Everything else off screen. A strip of somebody's terminal down the
        // edge of a recording sent to App Review is not a good look, and no
        // amount of window sizing reliably hides it.
        NSApp.hideOtherApplications(nil)
    }

    private static func insert(_ text: String) {
        guard let view = textView() else { return }
        view.window?.makeFirstResponder(view)
        view.insertText(text, replacementRange: view.selectedRange())
    }

    /// Types a string one character at a time, because a line that appears all
    /// at once reads as a paste rather than as someone using the app.
    private static func type(_ text: String, gap: TimeInterval = 0.055) {
        for character in text {
            after(gap) { insert(String(character)) }
        }
    }

    // MARK: - Timing

    /// Steps are queued against a running clock rather than nested, so the
    /// sequence above reads in the order it happens.
    private static var clock: TimeInterval = 0

    private static func after(_ gap: TimeInterval, _ body: @escaping () -> Void) {
        clock += gap
        DispatchQueue.main.asyncAfter(deadline: .now() + clock, execute: body)
    }

    /// How long the whole sequence takes, so the recorder knows when to stop.
    static var duration: TimeInterval { clock }
}

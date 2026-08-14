import AppKit

// Quill has no nib and no storyboard, so the app is assembled here by hand.
// NSDocumentController is touched early so it registers as the handler for the
// Apple Events Finder sends when a Markdown file is double-clicked.
let application = NSApplication.shared

if let request = ScreenshotRenderer.parse(CommandLine.arguments) {
    // Headless PNG render: no document controller, no menu, no untitled window.
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    exit(ScreenshotRenderer.run(request))
}

_ = NSDocumentController.shared

let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()

import AppKit

// Quill has no nib and no storyboard, so the app is assembled here by hand.
// NSDocumentController is touched early so it registers as the handler for the
// Apple Events Finder sends when a Markdown file is double-clicked.
let application = NSApplication.shared

if CommandLine.arguments.contains("--selftest") {
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    let document = CommandLine.arguments.last.flatMap { $0.hasSuffix(".md") ? $0 : nil }
    exit(SelfTest.run(document: document))
}

if let index = CommandLine.arguments.firstIndex(of: "--benchmark"),
   CommandLine.arguments.count > index + 1 {
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
    exit(Benchmark.run(path: CommandLine.arguments[index + 1]))
}

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

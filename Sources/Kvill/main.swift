import AppKit

// Kvill has no nib and no storyboard, so the app is assembled here by hand.
// NSDocumentController is touched early so it registers as the handler for the
// Apple Events Finder sends when a Markdown file is double-clicked.
let application = NSApplication.shared

/// Swallows the launch request to open whatever file paths are on the command
/// line.
///
/// `finishLaunching()` delivers the Apple Event that a normal launch carries, and
/// a document-based app answers it by opening every path in the arguments. In the
/// headless modes those paths are a PNG to write and a document to render, so
/// AppKit would put up "Kvill cannot open files in the PNG image format" and sit
/// in a modal loop waiting for a click that no one is there to give.
final class HeadlessDelegate: NSObject, NSApplicationDelegate {
    func application(_ sender: NSApplication, openFile filename: String) -> Bool { true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}

/// `NSApplication.delegate` is weak, so this has to outlive the call that sets it.
let headlessDelegate = HeadlessDelegate()

/// Brings AppKit up far enough to lay out text and draw, without any of the
/// document machinery a real launch starts.
func startHeadless() {
    application.delegate = headlessDelegate
    application.setActivationPolicy(.accessory)
    application.finishLaunching()
}

if CommandLine.arguments.contains("--selftest") {
    startHeadless()
    let document = CommandLine.arguments.last.flatMap { $0.hasSuffix(".md") ? $0 : nil }
    exit(SelfTest.run(document: document))
}

if let index = CommandLine.arguments.firstIndex(of: "--benchmark"),
   CommandLine.arguments.count > index + 1 {
    startHeadless()
    exit(Benchmark.run(path: CommandLine.arguments[index + 1]))
}

// Reads and sets the login item without going through the interface, so what
// the toggle does can be checked rather than taken on trust.
if let index = CommandLine.arguments.firstIndex(of: "--login-item") {
    startHeadless()
    let argument = CommandLine.arguments.count > index + 1
        ? CommandLine.arguments[index + 1] : "status"
    switch argument {
    case "on": BackgroundService.isEnabled = true
    case "off": BackgroundService.isEnabled = false
    default: break
    }
    print("setting: \(BackgroundService.isEnabled ? "on" : "off")")
    print("macOS says: \(BackgroundService.loginItemStatus)")
    exit(0)
}

if let request = ScreenshotRenderer.parse(CommandLine.arguments) {
    // Headless PNG render: no document controller, no menu, no untitled window.
    startHeadless()
    exit(ScreenshotRenderer.run(request))
}

// The first document controller created becomes the shared one, so Kvill's own
// subclass has to be built here, before AppKit reaches for the stock class.
let documentController = KvillDocumentController()

let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()

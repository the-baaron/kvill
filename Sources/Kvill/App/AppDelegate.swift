import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Kvill is one file per window and nothing else. With the last window shut
    /// there is no document, no palette and no state to come back to, so leaving
    /// the process running would only be an icon in the Dock that does nothing.
    /// Normally the app is its windows, so the last one closing ends it. With
    /// the background setting on it stays up instead, which is the whole point
    /// of that setting: the next document then costs a window rather than a
    /// process.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !BackgroundService.isEnabled
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(appDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: false)
        BackgroundService.apply()
        // Folders granted in earlier sessions, so a document opened from one has
        // its images straight away rather than after the sidebar is opened.
        FolderAccess.restore()

        // Only when this launch asked for it, and it clears the request as it
        // starts. Used to record the App Review demonstration.
        DemoDriver.runIfRequested()


        // With the background setting on, closing the last window leaves the app
        // running. It steps out of the Dock rather than sitting there empty, and
        // comes back the moment a document appears.
        for name in [NSWindow.willCloseNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main
            ) { _ in
                DispatchQueue.main.async { BackgroundService.updateActivationPolicy() }
            }
        }
    }

    /// Launching Kvill on its own opens a blank document, the same as TextEdit.
    /// Except at login, where nobody asked for one: an app that starts itself
    /// and puts an empty window in your face has misread the instruction.
    ///
    /// AppKit only asks this when the launch has nothing else to open, so a
    /// document double-clicked in the Finder never reaches here. Answering it
    /// somewhere else, on a delay, was a mistake: the delay ran before the
    /// launch's own Apple Event had been delivered, so opening a file put an
    /// empty Untitled window up beside it.
    ///
    /// There is no API for "this launch is the login item", so the clock decides:
    /// a login item starts within seconds of the console session, a person opens
    /// the app later. If the session start cannot be read at all, the window
    /// opens, because the bug this replaced left the app with no window, no Dock
    /// icon and no menu bar, and nothing at all to click.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        let opens = Self.opensBlankDocument(
            backgroundEnabled: BackgroundService.isEnabled,
            secondsSinceLogin: Self.consoleLoginDate.map { Date().timeIntervalSince($0) })
        // The answer can be right and still be wrong by the time the launch
        // finishes: AppKit asks this before delivering the Apple Event for a file
        // double-clicked in the Finder, so a launch that has a document to show
        // still looks empty here. The blank document is marked rather than
        // refused, and closed again if a file turns up behind it.
        if opens { (NSDocumentController.shared as? KvillDocumentController)?.isMakingLaunchPlaceholder = true }
        return opens
    }

    /// The decision on its own, with no clock and no defaults, so both branches
    /// can be checked. Neither can be reached otherwise: a test cannot log the
    /// user in, and a test machine is always hours past its own login.
    static func opensBlankDocument(
        backgroundEnabled: Bool, secondsSinceLogin: TimeInterval?
    ) -> Bool {
        // Without the background setting the app is its windows, so it always
        // opens one.
        guard backgroundEnabled else { return true }
        // Unreadable session start resolves towards being reachable, because the
        // bug this replaced left the app with no window, no Dock icon and no
        // menu bar, and nothing at all to click.
        guard let secondsSinceLogin else { return true }
        return secondsSinceLogin >= 90
    }

    /// When the console session began, from `utmpx`. Nil if it cannot be read.
    private static var consoleLoginDate: Date? {
        setutxent()
        defer { endutxent() }
        var newest: Date?
        while let entry = getutxent() {
            let record = entry.pointee
            guard record.ut_type == Int16(USER_PROCESS) else { continue }
            let line = withUnsafeBytes(of: record.ut_line) { raw -> String in
                let bytes = raw.bindMemory(to: CChar.self)
                guard let base = bytes.baseAddress else { return "" }
                return String(cString: base)
            }
            guard line == "console" else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec))
            if newest == nil || date > newest! { newest = date }
        }
        return newest
    }

    /// Brings the app back into the Dock and the menu bar and opens a document.
    ///
    /// The policy has to change first. An accessory app has no menu bar, so a
    /// window opened while still in that state arrives without one.
    private func showBlankDocument() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        // Marked for the same reason as at launch. With the background setting on
        // the app sits there with no windows, so double-clicking a file sends a
        // reopen as well as the file, and the reopen arrives first: this window is
        // opened for a click that already had a document behind it.
        let controller = NSDocumentController.shared as? KvillDocumentController
        controller?.isMakingLaunchPlaceholder = true
        _ = try? NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
        controller?.isMakingLaunchPlaceholder = false
    }

    /// Opening an app that is already running sends this instead of a launch,
    /// whether it comes from the Dock, Launchpad, Spotlight, TestFlight's Open
    /// button or `open -a`. With the background setting on that is the normal
    /// case, because the process is deliberately still there with no windows.
    /// Without this the click did nothing at all, every time.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasVisibleWindows, NSDocumentController.shared.documents.isEmpty else {
            return true
        }
        showBlankDocument()
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Opening a folder shows its Markdown files down the side of the window,
    /// and grants Kvill read access to everything in it, which is what makes
    /// images referenced beside a document load.
    @objc func openFolder(_ sender: Any?) {
        guard let folder = FolderAccess.request(startingAt: nil) else { return }
        (NSDocumentController.shared as? KvillDocumentController)?.openFolder(folder)
    }

    // MARK: - Theme commands

    @objc func selectPalette(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeManager.shared.selectPalette(id: id)
    }

    @objc func cyclePalette(_ sender: Any?) { ThemeManager.shared.cyclePalette() }

    @objc func toggleFollowSystem(_ sender: Any?) {
        ThemeManager.shared.followsSystemAppearance.toggle()
    }

    @objc func selectPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ThemeManager.shared.presetID = id
    }

    @objc func cyclePreset(_ sender: Any?) { ThemeManager.shared.cyclePreset() }

    @objc func selectTextSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = TextSize(rawValue: raw) else {
            return
        }
        ThemeManager.shared.textSize = size
    }

    @objc func increaseTextSize(_ sender: Any?) { ThemeManager.shared.stepTextSize(by: 1) }
    @objc func decreaseTextSize(_ sender: Any?) { ThemeManager.shared.stepTextSize(by: -1) }
    @objc func resetTextSize(_ sender: Any?) { ThemeManager.shared.resetTextSize() }

    @objc func selectLineWidth(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let width = LineWidth(rawValue: raw) else {
            return
        }
        ThemeManager.shared.lineWidth = width
    }

    @objc func toggleFocusMode(_ sender: Any?) { ThemeManager.shared.focusMode.toggle() }
    @objc func toggleTypewriter(_ sender: Any?) { ThemeManager.shared.typewriterScrolling.toggle() }

    /// Turning autosave off writes out whatever was already waiting, so edits
    /// made a moment before the setting changed are not stranded by it.
    @objc func toggleAutosave(_ sender: Any?) {
        let wanted = !ThemeManager.shared.liveMode
        if !wanted {
            for document in NSDocumentController.shared.documents
            where document.isDocumentEdited && document.fileURL != nil {
                document.save(withDelegate: nil, didSave: nil, contextInfo: nil)
            }
        }
        ThemeManager.shared.liveMode = wanted
    }
    @objc func toggleMarkers(_ sender: Any?) { ThemeManager.shared.alwaysShowMarkers.toggle() }

    // MARK: - Menu state

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let manager = ThemeManager.shared
        switch item.tag {
        case MenuTag.palette:
            item.state = (item.representedObject as? String) == manager.activePaletteID ? .on : .off
        case MenuTag.preset:
            item.state = (item.representedObject as? String) == manager.presetID ? .on : .off
        case MenuTag.textSize:
            item.state = (item.representedObject as? String) == manager.textSize.rawValue ? .on : .off
        case MenuTag.lineWidth:
            item.state = (item.representedObject as? String) == manager.lineWidth.rawValue ? .on : .off
        case MenuTag.focusMode:
            item.state = manager.focusMode ? .on : .off
        case MenuTag.typewriter:
            item.state = manager.typewriterScrolling ? .on : .off
        case MenuTag.markers:
            item.state = manager.alwaysShowMarkers ? .on : .off
        case MenuTag.autosave:
            item.state = manager.liveMode ? .on : .off
        case MenuTag.followSystem:
            item.state = manager.followsSystemAppearance ? .on : .off
        default:
            break
        }
        return true
    }

    // MARK: - Default handler

    /// Registers Kvill as the system's Markdown editor. This changes a setting
    /// outside the app, so it asks first.
    @objc func setAsDefaultMarkdownEditor(_ sender: Any?) {
        guard let markdown = UTType("net.daringfireball.markdown")
            ?? UTType(filenameExtension: "md") else {
            present(message: "Markdown type unavailable",
                    detail: "This system does not declare a Markdown content type.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Open all Markdown files in Kvill?"
        alert.informativeText = """
            Double-clicking a .md file in Finder will open it in Kvill from now on. \
            You can change this back at any time in Finder with Get Info › Open With.
            """
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL, toOpen: markdown
        ) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.present(
                    message: "Could not set Kvill as the default",
                    detail: error.localizedDescription)
            }
        }
    }

    private func present(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - Reference document

    /// Writes the bundled syntax reference somewhere durable and opens it as a
    /// normal document, so every feature can be seen rendered in the editor.
    @objc func openCheatSheet(_ sender: Any?) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let support else { return }
        let folder = support.appendingPathComponent("Kvill", isDirectory: true)
        let url = folder.appendingPathComponent("Markdown Reference.md")

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try MarkdownReference.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            present(message: "Could not open the reference", detail: error.localizedDescription)
            return
        }

        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                self.present(message: "Could not open the reference", detail: error.localizedDescription)
            }
        }
    }
}

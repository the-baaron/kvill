import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Foldout is one file per window and nothing else. With the last window shut
    /// there is no document, no palette and no state to come back to, so leaving
    /// the process running would only be an icon in the Dock that does nothing.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(appDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: false)
    }

    /// Launching Foldout on its own opens a blank document, the same as TextEdit.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

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
        case MenuTag.followSystem:
            item.state = manager.followsSystemAppearance ? .on : .off
        default:
            break
        }
        return true
    }

    // MARK: - Default handler

    /// Registers Foldout as the system's Markdown editor. This changes a setting
    /// outside the app, so it asks first.
    @objc func setAsDefaultMarkdownEditor(_ sender: Any?) {
        guard let markdown = UTType("net.daringfireball.markdown")
            ?? UTType(filenameExtension: "md") else {
            present(message: "Markdown type unavailable",
                    detail: "This system does not declare a Markdown content type.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Open all Markdown files in Foldout?"
        alert.informativeText = """
            Double-clicking a .md file in Finder will open it in Foldout from now on. \
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
                    message: "Could not set Foldout as the default",
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
        let folder = support.appendingPathComponent("Foldout", isDirectory: true)
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

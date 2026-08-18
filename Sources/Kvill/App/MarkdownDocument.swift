import AppKit

/// One Markdown file. Kvill is strictly one file per window: `NSDocument` gives
/// that for free, along with autosave, versions, and Finder double-click opening.
/// The `@objc` name is what `NSDocumentClass` in Info.plist looks up, so it must
/// stay stable and unmangled.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {

    private var content = ""
    /// Encoding the file was read with, so saving round-trips rather than
    /// silently rewriting a Latin-1 file as UTF-8.
    private var encoding: String.Encoding = .utf8

    private(set) weak var controller: DocumentViewController?

    /// Watches the file for changes made by anything other than this window.
    private var watcher: FileWatcher?
    /// Exactly what this document last put on disk, so its own writes are not
    /// read back as somebody else's edit. Compared by content rather than by
    /// timing: autosave runs every half second, and any window in which a write
    /// counts as "recent" is a race that eventually loses.
    private var lastWritten: String?

    /// On unless the setting has been turned off, in which case Kvill becomes an
    /// ordinary Cmd-S editor and AppKit puts up its own "do you want to save"
    /// sheet on close. Read fresh every time rather than captured once, so the
    /// toggle takes effect on documents that are already open.
    override class var autosavesInPlace: Bool { ThemeManager.shared.liveMode }


    override var windowNibName: NSNib.Name? { nil }

    // MARK: - Windows

    override func makeWindowControllers() {
        let windowController = DocumentWindowController.create()
        addWindowController(windowController)
        if let split = windowController.contentViewController as? DocumentSplitViewController {
            adopt(split.page)
        }
    }

    /// Copies what is on screen into this document's own store.
    ///
    /// Called before the document gives up the window it is showing in. After
    /// this the document can write itself correctly with no editor at all, which
    /// matters because `controller` is weak and the view it points at is about
    /// to be taken out of the window.
    func captureText() {
        guard let text = controller?.text else { return }
        content = text
    }

    /// Takes ownership of an editor. The editor is this document's and no other
    /// document's, ever.
    ///
    /// `data(ofType:)` reads the text out of `controller`, which makes the editor
    /// the document's source of truth. Two documents sharing one editor is
    /// therefore data loss waiting for a timer: the one being replaced autosaves
    /// half a second later, reads the editor, finds the text of the file that
    /// replaced it, and writes that into its own path. That shipped, and it
    /// rewrote four of someone's notes with each other's contents.
    ///
    /// A window may move between documents, because switching files in the
    /// sidebar reuses it. An editor may not. Each document builds its own and
    /// the window is told which one to show.
    func adopt(_ viewController: DocumentViewController) {
        controller = viewController
        normalizeSource()
        startWatching()
        viewController.documentURL = fileURL
        viewController.documentTitle = displayName
        viewController.loadText(content)
        viewController.onTextChange = { [weak self] in
            // Only the dirty flag. Copying the text into `content` here meant
            // copying the whole file on every keystroke; it is read from the
            // editor when it is actually needed, which is when saving.
            self?.updateChangeCount(.changeDone)
        }
    }

    // MARK: - Reading and writing

    override func read(from data: Data, ofType typeName: String) throws {
        if let text = String(data: data, encoding: .utf8) {
            content = text
            encoding = .utf8
        } else {
            // Fall back to whatever encoding the system can identify rather than
            // failing outright on an older file.
            var converted: NSString?
            let detected = NSString.stringEncoding(
                for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
            guard detected != 0, let converted else {
                throw NSError(
                    domain: NSCocoaErrorDomain, code: NSFileReadInapplicableStringEncodingError,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Kvill could not work out this file's text encoding."
                    ])
            }
            content = converted as String
            encoding = String.Encoding(rawValue: detected)
        }
        normalizeSource()
        lastWritten = content
        controller?.loadText(content)
    }

    /// Rewrites setext headings as `#` ones and pads table cells so their columns
    /// line up. The change is left unsaved: opening a file should not rewrite it
    /// on disk. It goes along with the next save, and Undo puts it back.
    private func normalizeSource() {
        if let converted = SetextNormalizer.normalized(content) { content = converted }
        if let padded = TableFormatter.normalized(content) { content = padded }
    }

    override var fileURL: URL? {
        didSet {
            // Saving an untitled document gives images somewhere to live, and
            // makes any relative paths already written resolve.
            controller?.documentURL = fileURL
            controller?.documentTitle = displayName
            startWatching()
        }
    }

    // MARK: - Following the file

    /// Watches the file so the window always shows what is actually on disk.
    ///
    /// Together with the half-second autosave this makes the file the single
    /// copy of the truth: this window writes what you type almost immediately,
    /// and picks up anything written by anything else almost immediately, so
    /// the two can never drift far enough apart to need a conflict dialogue.
    private func startWatching() {
        watcher = nil
        guard let url = fileURL else { return }
        watcher = FileWatcher(url: url) { [weak self] in
            self?.fileChangedOnDisk()
        }
    }

    private func fileChangedOnDisk() {
        guard let url = fileURL else { return }
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .utf8) else { return }

        // Our own write coming back around.
        guard text != lastWritten else { return }
        // Already showing it.
        guard text != (controller?.text ?? content) else { return }

        // Out of live mode nothing moves on its own. The page keeps showing what
        // was opened, however many times the file is rewritten behind it, and
        // the only sign is a note that it happened. Remembered, because saving
        // over it later has to ask first, and because being able to look at what
        // arrived is the whole point of being told.
        guard ThemeManager.shared.liveMode else {
            diskText = text
            controller?.noteChangedOnDisk()
            return
        }

        // There are unsaved edits here. Reloading would throw them away, and
        // writing from inside a file-change handler is how a write loop starts.
        // The autosave already scheduled lands within half a second and settles
        // it, so this does nothing at all.
        guard !isDocumentEdited else { return }

        content = text
        lastWritten = text
        controller?.replaceKeepingPlace(with: text)
        updateChangeCount(.changeCleared)
    }

    /// What the file held when it last changed behind this window, out of live
    /// mode. Nil once it has been reloaded or deliberately overwritten.
    private(set) var diskText: String?

    /// Whether the file has moved on since this window last agreed with it.
    var hasChangedOnDisk: Bool { diskText != nil }

    /// Reads the file again, replacing what is on screen.
    ///
    /// AppKit's own revert, so the undo stack, the change count and the modified
    /// dot are all handled by the framework rather than by arithmetic here.
    @objc func reloadFromDisk(_ sender: Any?) {
        guard let url = fileURL else { return }
        try? revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
        diskText = nil
    }

    /// Whether saving now would write over something this window never saw.
    ///
    /// Only out of live mode. In live mode the page already holds whatever the
    /// file holds, so there is nothing to write over.
    private func wouldOverwriteSomethingUnseen(_ operation: NSDocument.SaveOperationType) -> Bool {
        guard !ThemeManager.shared.liveMode, hasChangedOnDisk else { return false }
        return operation == .saveOperation
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = controller?.text ?? content
        content = text
        lastWritten = text
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else {
            throw NSError(
                domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError,
                userInfo: [NSLocalizedDescriptionKey: "Kvill could not encode this document for saving."])
        }
        return data
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // Tables are squared up on the way to disk, so a file is tidy even if
        // the caret never left the table being typed into. Only on a save the
        // user asked for: doing it on every autosave would reflow the columns
        // under the cursor mid-word, which is the thing the caret-leave rule
        // exists to avoid.
        // Somebody else wrote this file while it sat here unwatched, and this
        // save would put it back the way this window remembers it. Ask, and
        // offer to show what would go, because "are you sure" is not a question
        // anyone can answer without seeing the answer.
        if wouldOverwriteSomethingUnseen(saveOperation) {
            askBeforeOverwriting { [weak self] proceed in
                guard let self else { return }
                guard proceed else {
                    completionHandler(CocoaError(.userCancelled))
                    return
                }
                self.diskText = nil
                self.save(to: url, ofType: typeName, for: saveOperation,
                          completionHandler: completionHandler)
            }
            return
        }

        if saveOperation != .autosaveInPlaceOperation,
           saveOperation != .autosaveElsewhereOperation {
            controller?.formatTables()
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            completionHandler(error)
            // Autosaves happen on their own schedule; confirming those would be
            // noise. This is only for a save the user asked for.
            guard error == nil,
                  saveOperation != .autosaveInPlaceOperation,
                  saveOperation != .autosaveElsewhereOperation else { return }
            self?.controller?.confirmSaved()
        }
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        controller?.loadText(content)
        updateChangeCount(.changeCleared)
    }
}

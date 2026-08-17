import AppKit

/// Decides what Kvill will actually open.
///
/// The stock behaviour is to check a file's type and, when it does not match one
/// the app declares, refuse with a modal alert: "Kvill cannot open files in the
/// PNG image format." That is the wrong answer twice over. Dropping a folder of
/// notes and screenshots on the icon should open the notes and leave the rest
/// alone, and a type check is the wrong question anyway, because Kvill can show
/// any text file whatever its extension says.
///
/// So the question asked here is the one that matters: does this file decode as
/// text? If it does, open it. If it does not, skip it quietly.
final class KvillDocumentController: NSDocumentController {

    /// How long a document sits on an edit before writing it.
    ///
    /// The default is 30 seconds. That is far too long here, because a window
    /// reloads whenever its file changes underneath it: an edit that has not
    /// been written yet is a conflict waiting to happen. Half a second is short
    /// enough that the file on disk is always what is on screen, and long enough
    /// that a burst of typing is one write rather than fifty.
    static let saveDelay: TimeInterval = 0.5

    override init() {
        super.init()
        autosavingDelay = Self.saveDelay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        autosavingDelay = Self.saveDelay
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        // A folder is not a document. It is a place to find one, and choosing it
        // is also what grants Kvill read access to everything inside, which is
        // what makes images beside a document load.
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            openFolder(url)
            completionHandler(nil, false, CocoaError(.userCancelled))
            return
        }

        guard KvillDocumentController.isReadableAsText(url) else {
            // `userCancelled` is the one error AppKit shows nothing for, which is
            // exactly right: the user asked for something Kvill does not do, and
            // an alert would not tell them anything the missing window does not.
            completionHandler(nil, false, CocoaError(.userCancelled))
            return
        }
        super.openDocument(
            withContentsOf: url, display: displayDocument, completionHandler: completionHandler)
    }

    /// Shows `url` in the window `current` is using, instead of opening another
    /// window, so reading through a folder does not leave one window per file.
    ///
    /// The window moves between documents. The editor never does. Each document
    /// builds its own `DocumentViewController` and the window is told which one
    /// to show, because a document reads its text out of its editor when it
    /// saves: two documents sharing one editor means the outgoing document
    /// autosaves the incoming file's text into its own path. That is not a bug
    /// that can be patched around, it is what sharing an editor means, and it
    /// rewrote four of someone's notes with each other's contents before this
    /// was understood.
    ///
    /// The outgoing document keeps its own editor, still holding its own text,
    /// and is asked to capture that text before it lets go of the window, so its
    /// final autosave writes what was actually typed into it.
    @discardableResult
    func openInPlace(_ url: URL, replacing current: NSDocument) -> Bool {
        // Compared by resolved path. The sidebar and NSDocument can hold one file
        // as /tmp/x and /private/tmp/x, and two spellings would defeat every
        // check below.
        let wanted = url.standardizedFileURL.resolvingSymlinksInPath()
        func isWanted(_ other: URL?) -> Bool {
            other?.standardizedFileURL.resolvingSymlinksInPath() == wanted
        }
        if isWanted(current.fileURL) { return true }

        // Already open in a window of its own: raise that rather than showing the
        // same file twice. "In a window" matters, because a document on its way
        // out sits here briefly with none, and treating that one as on screen
        // made every other click in the sidebar do nothing at all.
        if let already = documents.first(where: { isWanted($0.fileURL) }) {
            if let window = already.windowControllers.first?.window, window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return true
            }
            already.close()
        }

        // An untitled document with unsaved work has nowhere to autosave to, so
        // it keeps its window and the new file gets one of its own.
        guard current.fileURL != nil || !current.isDocumentEdited,
              let windowController = current.windowControllers.first,
              let window = windowController.window,
              let fresh = try? makeDocument(withContentsOf: url, ofType: typeName(for: url))
        else { return false }

        // Before anything is detached, so it cannot be reading a stale editor.
        (current as? MarkdownDocument)?.captureText()

        addDocument(fresh)
        let editor = DocumentViewController()
        (fresh as? MarkdownDocument)?.adopt(editor)

        current.removeWindowController(windowController)
        fresh.addWindowController(windowController)

        // Setting a content view controller resizes the window to that view's
        // fitting size, and the editor has no intrinsic one, so the frame is put
        // back afterwards.
        let frame = window.frame
        window.contentViewController = editor
        window.setFrame(frame, display: true)

        current.autosave(withImplicitCancellability: false) { _ in current.close() }
        return true
    }

    private func typeName(for url: URL) -> String {
        (try? typeForContents(of: url)) ?? "net.daringfireball.markdown"
    }

    /// Opens a folder: remember it, then show its tree beside whichever document
    /// is already open, or beside the first one in the folder.
    func openFolder(_ folder: URL) {
        FolderAccess.remember(folder)

        if let controller = NSApp.keyWindow?.contentViewController as? DocumentViewController {
            controller.showFolder(folder)
            return
        }
        // Nothing open to attach it to, so the first document in the folder
        // becomes the window the tree lives in.
        let first = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?
            .first { FileTreeView.isMarkdown($0) }

        guard let first else { return }
        openDocument(withContentsOf: first, display: true) { document, _, _ in
            guard let controller = document?.windowControllers.first?
                .contentViewController as? DocumentViewController else { return }
            controller.showFolder(folder)
        }
    }

    /// True when the start of the file reads as text.
    ///
    /// Only the first few kilobytes are looked at, so this stays instant on a
    /// large file. A NUL byte settles it: no text encoding Kvill would open puts
    /// one in the first page, and every binary format has one early.
    static func isReadableAsText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        let sample = (try? handle.read(upToCount: 8192)) ?? Data()
        // An empty file is a new document waiting to be written into.
        guard !sample.isEmpty else { return true }
        guard !sample.contains(0) else { return false }

        if String(data: sample, encoding: .utf8) != nil { return true }
        // A multi-byte character can straddle the end of the sample, so a failure
        // on the last few bytes is not proof of anything.
        if sample.count == 8192, String(data: sample.dropLast(4), encoding: .utf8) != nil {
            return true
        }
        // Not UTF-8, but the system may still recognise the encoding, which is
        // what `MarkdownDocument.read` falls back to.
        return NSString.stringEncoding(
            for: sample, encodingOptions: nil, convertedString: nil, usedLossyConversion: nil) != 0
    }
}

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

    /// Opens `url` into a window that is already on screen, in place of what it
    /// is showing.
    ///
    /// Choosing a file in the sidebar used to call `openDocument(display: true)`,
    /// which is by definition a new document in a new window, so a folder of
    /// twelve notes read on screen as twelve windows. One file per window is
    /// still the model; this only says that *switching* reuses the window you
    /// are looking at, the way tabs behave, without any tab bar appearing.
    ///
    /// The window controller is moved between documents rather than the text
    /// being swapped underneath one, so each document keeps its own undo stack,
    /// dirty state and autosave.
    @discardableResult
    func openInPlace(_ url: URL, replacing current: NSDocument) -> Bool {
        // Compared by resolved path, not by URL. The sidebar and NSDocument can
        // hold the same file as /tmp/x and /private/tmp/x, and two spellings of
        // one path would defeat every check below.
        let wanted = url.standardizedFileURL.resolvingSymlinksInPath()
        func isWanted(_ other: URL?) -> Bool {
            other?.standardizedFileURL.resolvingSymlinksInPath() == wanted
        }

        if isWanted(current.fileURL) { return true }

        // Already open with a window of its own: raise that instead of opening a
        // second copy, which AppKit would otherwise refuse in a confusing way.
        //
        // "With a window" is the whole point. The document being replaced is
        // closed only once its autosave finishes, so for a moment it is still on
        // this controller's list with no window controller left on it. Switching
        // back to a file just left found that one, had nothing to raise, and
        // reported success, so the click did nothing and the window went on
        // showing the previous file. It looked like the sidebar was ignoring
        // every other click. Anything window-less here is on its way out and is
        // closed now rather than being handed back as if it were on screen.
        if let already = documents.first(where: { isWanted($0.fileURL) }) {
            if let window = already.windowControllers.first?.window, window.isVisible {
                window.makeKeyAndOrderFront(nil)
                return true
            }
            already.close()
        }

        // An untitled document with unsaved work has nowhere to autosave to, so
        // its window is left alone and the new file gets its own.
        guard current.fileURL != nil || !current.isDocumentEdited,
              let windowController = current.windowControllers.first,
              let fresh = try? makeDocument(withContentsOf: url, ofType: typeName(for: url))
        else { return false }

        addDocument(fresh)
        current.removeWindowController(windowController)
        // Before the new one takes it. The outgoing document keeps a reference
        // to the view controller otherwise, and writes its own file back into it
        // as it closes.
        (current as? MarkdownDocument)?.releaseController()
        fresh.addWindowController(windowController)
        (fresh as? MarkdownDocument)?.bind(to: windowController)
        // Autosave is in place and on a delay, so the outgoing document is asked
        // to write before it goes rather than being closed on top of edits that
        // have not landed yet.
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

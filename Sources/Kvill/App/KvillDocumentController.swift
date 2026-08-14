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

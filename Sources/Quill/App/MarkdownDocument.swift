import AppKit

/// One Markdown file. Quill is strictly one file per window: `NSDocument` gives
/// that for free, along with autosave, versions, and Finder double-click opening.
/// The `@objc` name is what `NSDocumentClass` in Info.plist looks up, so it must
/// stay stable and unmangled.
@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {

    private var content = ""
    /// Encoding the file was read with, so saving round-trips rather than
    /// silently rewriting a Latin-1 file as UTF-8.
    private var encoding: String.Encoding = .utf8

    private weak var controller: DocumentViewController?

    override class var autosavesInPlace: Bool { true }

    override var windowNibName: NSNib.Name? { nil }

    // MARK: - Windows

    override func makeWindowControllers() {
        let windowController = DocumentWindowController.create()
        addWindowController(windowController)

        guard let viewController = windowController.contentViewController as? DocumentViewController else {
            return
        }
        controller = viewController
        viewController.loadText(content)
        viewController.onTextChange = { [weak self, weak viewController] in
            guard let self, let viewController else { return }
            self.content = viewController.text
            self.updateChangeCount(.changeDone)
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
                        NSLocalizedDescriptionKey: "Quill could not work out this file's text encoding."
                    ])
            }
            content = converted as String
            encoding = String.Encoding(rawValue: detected)
        }
        controller?.loadText(content)
    }

    override func data(ofType typeName: String) throws -> Data {
        let text = controller?.text ?? content
        content = text
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else {
            throw NSError(
                domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError,
                userInfo: [NSLocalizedDescriptionKey: "Quill could not encode this document for saving."])
        }
        return data
    }

    override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        controller?.loadText(content)
        updateChangeCount(.changeCleared)
    }
}

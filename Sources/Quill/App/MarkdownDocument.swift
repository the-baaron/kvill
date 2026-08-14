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
        normalizeSetextHeadings()
        viewController.documentURL = fileURL
        viewController.documentTitle = displayName
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
        normalizeSetextHeadings()
        controller?.loadText(content)
    }

    /// Rewrites setext headings as `#` ones. The change is left unsaved: opening
    /// a file should not rewrite it on disk. It goes along with the next save,
    /// and Undo puts it back.
    private func normalizeSetextHeadings() {
        guard let converted = SetextNormalizer.normalized(content) else { return }
        content = converted
    }

    override var fileURL: URL? {
        didSet {
            // Saving an untitled document gives images somewhere to live, and
            // makes any relative paths already written resolve.
            controller?.documentURL = fileURL
            controller?.documentTitle = displayName
        }
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

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
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

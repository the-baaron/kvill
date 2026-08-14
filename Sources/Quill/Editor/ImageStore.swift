import AppKit

/// Loads and caches images referenced by the document.
///
/// The styler asks for an image's display size on every restyle, which happens
/// on every keystroke, so this has to be cheap. Entries are keyed by path and
/// modification date, so editing an image on disk picks up the new version
/// without needing to reopen the document.
final class ImageStore {

    static let shared = ImageStore()

    private struct Key: Hashable {
        let path: String
        let modified: Date?
        let size: Int64
    }

    private var cache: [Key: NSImage] = [:]
    /// Paths that failed to load, so a broken link is not retried on every keystroke.
    private var failed: Set<String> = []

    private init() {}

    /// Resolves a Markdown destination against the document's folder.
    ///
    /// Returns nil for anything that is not a local file, including `http:` URLs:
    /// fetching those would mean network access during layout.
    func resolve(_ destination: String, relativeTo base: URL?) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // A destination may carry a title: ![alt](path "Title")
        var path = trimmed
        if let quote = path.firstIndex(where: { $0 == "\"" || $0 == "'" }) {
            path = String(path[path.startIndex..<quote]).trimmingCharacters(in: .whitespaces)
        }
        if path.hasPrefix("<"), path.hasSuffix(">") {
            path = String(path.dropFirst().dropLast())
        }
        guard !path.isEmpty else { return nil }

        if let url = URL(string: path), let scheme = url.scheme?.lowercased() {
            return scheme == "file" ? url : nil
        }

        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        if decoded.hasPrefix("~") {
            return URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath)
        }
        guard let base else { return nil }
        return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    func image(at url: URL) -> NSImage? {
        let path = url.path
        if failed.contains(path) { return nil }

        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let key = Key(
            path: path,
            modified: attributes?[.modificationDate] as? Date,
            size: (attributes?[.size] as? NSNumber)?.int64Value ?? 0)

        if let cached = cache[key] { return cached }

        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            failed.insert(path)
            return nil
        }
        cache[key] = image
        return image
    }

    /// Size to draw an image at, fitted to the column and capped in height so a
    /// tall screenshot does not push the rest of the document off the page.
    func displaySize(for image: NSImage, measure: CGFloat, maximumHeight: CGFloat) -> NSSize {
        let natural = image.size
        var width = min(natural.width, measure)
        var height = width * natural.height / natural.width

        if height > maximumHeight {
            height = maximumHeight
            width = height * natural.width / natural.height
        }
        return NSSize(width: max(width, 1), height: max(height, 1))
    }

    /// Clears the failure list so a link fixed on disk is retried.
    func forgetFailures() {
        failed.removeAll()
    }
}

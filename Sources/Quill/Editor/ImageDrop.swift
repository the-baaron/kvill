import AppKit
import UniformTypeIdentifiers

/// Turns a drag of image files, or of raw image data from a browser or Photos,
/// into Markdown at the drop point.
///
/// Nothing is written over: a file already inside the document's folder is
/// referenced where it lies, and anything from outside is copied into an
/// `images/` folder beside the document under a name that is not already taken.
enum ImageDrop {

    /// Whether this drag carries something worth embedding.
    static func canAccept(_ info: NSDraggingInfo) -> Bool {
        !imageURLs(in: info.draggingPasteboard).isEmpty || imageData(in: info.draggingPasteboard) != nil
    }

    static func imageURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options)
        return (objects as? [URL]) ?? []
    }

    static func imageData(in pasteboard: NSPasteboard) -> (data: Data, ext: String)? {
        if let data = pasteboard.data(forType: .png) { return (data, "png") }
        if let data = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return (png, "png")
        }
        return nil
    }

    /// Markdown for everything in the drag, one image per line.
    static func markdown(for info: NSDraggingInfo, documentURL: URL?) -> String? {
        var lines: [String] = []

        for url in imageURLs(in: pasteboard(info)) {
            guard let reference = reference(for: url, documentURL: documentURL) else { continue }
            let alt = url.deletingPathExtension().lastPathComponent
            lines.append("![\(alt)](\(reference))")
        }

        if lines.isEmpty, let payload = imageData(in: pasteboard(info)) {
            guard let url = write(payload.data, ext: payload.ext, documentURL: documentURL),
                  let reference = reference(for: url, documentURL: documentURL) else { return nil }
            lines.append("![image](\(reference))")
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func pasteboard(_ info: NSDraggingInfo) -> NSPasteboard {
        info.draggingPasteboard
    }

    // MARK: - Filing

    /// Path to write into the document, copying the file next to the document
    /// first if it lives somewhere else.
    private static func reference(for url: URL, documentURL: URL?) -> String? {
        guard let documentURL else {
            // Nowhere to be relative to yet, so point at the file where it is.
            return escape(url.path)
        }
        let folder = documentURL.deletingLastPathComponent().standardizedFileURL
        let source = url.standardizedFileURL

        if let relative = relativePath(of: source, under: folder) {
            return escape(relative)
        }

        let images = folder.appendingPathComponent("images", isDirectory: true)
        guard let copied = copy(source, into: images) else { return escape(source.path) }
        return escape("images/" + copied.lastPathComponent)
    }

    /// A path relative to `folder`, or nil when the file is outside it.
    private static func relativePath(of url: URL, under folder: URL) -> String? {
        let target = url.pathComponents
        let base = folder.pathComponents
        guard target.count > base.count, Array(target.prefix(base.count)) == base else { return nil }
        return target.dropFirst(base.count).joined(separator: "/")
    }

    private static func copy(_ source: URL, into folder: URL) -> URL? {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        var destination = folder.appendingPathComponent(source.lastPathComponent)
        if manager.fileExists(atPath: destination.path) {
            // Same file already filed here? Then reuse it rather than making a copy.
            if let a = try? Data(contentsOf: source), let b = try? Data(contentsOf: destination), a == b {
                return destination
            }
            let name = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var counter = 2
            repeat {
                let candidate = ext.isEmpty ? "\(name) \(counter)" : "\(name) \(counter).\(ext)"
                destination = folder.appendingPathComponent(candidate)
                counter += 1
            } while manager.fileExists(atPath: destination.path) && counter < 1000
        }

        do {
            try manager.copyItem(at: source, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// Writes pasted image data to a file so it can be referenced.
    private static func write(_ data: Data, ext: String, documentURL: URL?) -> URL? {
        let folder: URL
        if let documentURL {
            folder = documentURL.deletingLastPathComponent()
                .appendingPathComponent("images", isDirectory: true)
        } else {
            // An unsaved document has no folder of its own yet, so the data goes
            // somewhere durable rather than into the user's own directories.
            guard let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
            folder = support
                .appendingPathComponent("Quill", isDirectory: true)
                .appendingPathComponent("Dropped Images", isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let name = "Image " + stamp.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent("\(name).\(ext)")

        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Wraps a path in angle brackets when it holds characters Markdown would
    /// otherwise mis-read. Percent-encoding also works, but turns a screenshot
    /// called "Schermafbeelding 2026-08-14 om 10.38.56.png" into an unreadable
    /// smear of `%20` in a caption the user has to look at.
    private static func escape(_ path: String) -> String {
        let awkward = CharacterSet(charactersIn: " ()<>\t")
        guard path.rangeOfCharacter(from: awkward) != nil else { return path }
        let inner = path
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
        return "<\(inner)>"
    }
}

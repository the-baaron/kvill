import AppKit

/// Remembers folders the user has opened, so the files inside them can be read.
///
/// The sandbox grants what the user chose and nothing else. Opening a document
/// grants that document; the picture sitting next to it is a different file and
/// is refused. Choosing the *folder* grants the folder and everything under it,
/// which is why the file tree and working images are the same feature.
///
/// A security-scoped bookmark makes that grant survive a relaunch. Without one
/// it would have to be asked for again every morning.
enum FolderAccess {

    private static let key = "kvill.folderBookmarks"

    /// Folders currently opened for access, and the URL that owns each scope so
    /// it can be closed again.
    private static var open: [String: URL] = [:]

    // MARK: - Granting

    /// Asks for a folder and remembers it. Returns nil if the user cancels.
    ///
    /// The panel is the grant: there is no way to obtain this access silently,
    /// and there should not be.
    static func request(startingAt suggestion: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggestion
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder to browse. Kvill will be able to read the "
            + "files in it, including images your documents refer to."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        remember(url)
        return url
    }

    /// Stores a bookmark for a folder the user has chosen.
    static func remember(_ folder: URL) {
        guard let data = try? folder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        stored[folder.standardizedFileURL.path] = data
        UserDefaults.standard.set(stored, forKey: key)
        _ = beginAccess(to: folder)
    }

    /// Folders the user has granted before, most recent last.
    static var remembered: [URL] {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        return stored.keys.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: - Using

    /// Opens the security scope for a folder, resolving its bookmark if needed.
    @discardableResult
    static func beginAccess(to folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        if open[path] != nil { return true }

        // A folder chosen in this session is already accessible; one from a
        // previous session has to be resolved from its bookmark first.
        guard let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Data],
              let data = stored[path] else {
            open[path] = folder
            return true
        }

        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data, options: .withSecurityScope,
            relativeTo: nil, bookmarkDataIsStale: &stale) else { return false }
        guard resolved.startAccessingSecurityScopedResource() else { return false }
        open[path] = resolved
        if stale { remember(resolved) }
        return true
    }

    /// True when this file sits inside a folder the user has granted, which is
    /// what makes an image beside a document readable.
    ///
    /// Both kinds of grant count: one bookmarked from an earlier session, and
    /// one opened a moment ago and not yet written down. Checking only the
    /// stored ones meant a folder opened during this session did not count as
    /// open, which is plainly wrong.
    static func isReachable(_ file: URL) -> Bool {
        let path = file.standardizedFileURL.path
        for folder in open.keys where path.hasPrefix(folder + "/") { return true }
        for folder in remembered where path.hasPrefix(folder.path + "/") {
            if beginAccess(to: folder) { return true }
        }
        return false
    }

    /// Opens every remembered folder at launch, so documents in them work
    /// straight away rather than after a visit to the sidebar.
    static func restore() {
        for folder in remembered { _ = beginAccess(to: folder) }
    }

    static func forget(_ folder: URL) {
        let path = folder.standardizedFileURL.path
        if let scoped = open.removeValue(forKey: path) {
            scoped.stopAccessingSecurityScopedResource()
        }
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
        stored.removeValue(forKey: path)
        UserDefaults.standard.set(stored, forKey: key)
    }
}

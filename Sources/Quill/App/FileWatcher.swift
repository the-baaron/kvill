import Foundation

/// Tells you when a file changes on disk.
///
/// This is a plain dispatch source on a file descriptor, which is the system's
/// own mechanism: no polling, no timer, and the kernel does the noticing. A
/// write from another program, a `git checkout`, or a sync client all arrive the
/// same way.
///
/// Editors commonly replace a file rather than write into it, which invalidates
/// the descriptor. That arrives as a delete or rename, and the watch is set up
/// again on the new file rather than going quiet.
final class FileWatcher {

    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    /// Guards against a re-arm loop when the file is gone for good.
    private var rearming = false

    init?(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        guard start() else { return nil }
    }

    deinit {
        stop()
    }

    @discardableResult
    private func start() -> Bool {
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) || flags.contains(.revoke) {
                self.rearm()
            } else {
                self.onChange()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.descriptor >= 0 else { return }
            close(self.descriptor)
            self.descriptor = -1
        }
        source.resume()
        self.source = source
        return true
    }

    /// A replaced file: the old descriptor is dead, so watch the new one. The
    /// short delay is for the gap between the writer's rename and the new file
    /// appearing.
    private func rearm() {
        guard !rearming else { return }
        rearming = true
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.rearming = false
            if self.start() { self.onChange() }
        }
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

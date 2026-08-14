import AppKit
import ServiceManagement

/// Keeps Kvill running with no windows open, so opening a file costs a window
/// rather than a whole process.
///
/// A first document costs about 100ms, almost all of it starting AppKit and
/// talking to the window server. A second one, in a process that is already up,
/// costs about 25ms. Staying resident is the difference between the two, and
/// there is no code that makes a cold start meaningfully faster.
///
/// Off by default. An editor that installs itself into your login items
/// uninvited has answered a question nobody asked.
enum BackgroundService {

    /// What macOS thinks, rather than what the setting says. `Kvill
    /// --login-item` prints it, so the two can be compared without guessing.
    static var loginItemStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "not registered"
        case .requiresApproval: return "requires approval in System Settings"
        case .notFound: return "not found"
        @unknown default: return "unknown"
        }
    }

    /// Whether the app stays running with no windows and starts at login.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "kvill.staysRunning") }
        set {
            UserDefaults.standard.set(newValue, forKey: "kvill.staysRunning")
            apply()
        }
    }

    /// Registers or unregisters the login item and moves the app in or out of
    /// the Dock to match.
    static func apply() {
        register(isEnabled)
        updateActivationPolicy()
    }

    private static func register(_ wanted: Bool) {
        // The service is the app itself, which is what SMAppService.mainApp is
        // for: no helper bundle, no extra entitlement, and the user can turn it
        // off again in System Settings without coming back here.
        let service = SMAppService.mainApp
        do {
            switch (wanted, service.status) {
            case (true, .enabled):
                break                       // already there
            case (true, _):
                try service.register()      // includes .requiresApproval, where
                                            // registering again is the way to
                                            // prompt for it
            case (false, .notRegistered):
                break                       // already gone
            case (false, _):
                // Anything that is not notRegistered is still an item, waiting
                // for approval included. Unregistering only from .enabled left
                // a pending one behind.
                try service.unregister()
            }
        } catch {
            // Registration can be refused, most often because the user has
            // denied it in System Settings. The setting stays where they put it
            // and the app carries on; nothing here is worth an alert.
            FileHandle.standardError.write(
                Data("Login item: \(error.localizedDescription)\n".utf8))
        }
    }

    /// With no windows open and the setting on, the app steps out of the Dock
    /// and the menu bar. It comes back the moment a document opens.
    ///
    /// Without this, turning the setting on would leave an icon sitting in the
    /// Dock all day doing nothing, which is a worse trade than the 75ms it buys.
    static func updateActivationPolicy() {
        guard isEnabled else {
            if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
            return
        }
        let hasDocuments = !NSDocumentController.shared.documents.isEmpty
        let wanted: NSApplication.ActivationPolicy = hasDocuments ? .regular : .accessory
        guard NSApp.activationPolicy() != wanted else { return }
        NSApp.setActivationPolicy(wanted)
        if wanted == .regular { NSApp.activate(ignoringOtherApps: true) }
    }
}

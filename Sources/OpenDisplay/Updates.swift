import AppKit
import Sparkle

/// Automatic updates with Sparkle. The feed (SUFeedURL in Info.plist) is the appcast.xml of the latest GitHub release.
/// Sparkle installs an update only if it has a valid EdDSA signature for the public key in Info.plist (SUPublicEDKey),
/// and the same code signature as this app.
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    private var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Starts the updater: it checks on its schedule (once a day) when automatic checks are on.
    func start() {
        _ = controller
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Checks without a window, like the daily check: it shows a window only when it finds an update.
    func checkForUpdatesInBackground() {
        controller.updater.checkForUpdatesInBackground()
    }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    // MARK: SPUStandardUserDriverDelegate

    /// OpenDisplay is a menu bar app without a Dock icon. "Gentle" reminders show a found update without taking the
    /// focus from the app you are using, which Sparkle recommends for background apps.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}

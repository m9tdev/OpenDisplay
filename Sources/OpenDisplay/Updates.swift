import AppKit
import DisplayPolicy
import Sparkle

/// Automatic updates with Sparkle. The feed (SUFeedURL in Info.plist) is the appcast.xml of the latest GitHub release.
/// Sparkle installs an update only if it has a valid EdDSA signature for the public key in Info.plist (SUPublicEDKey),
/// and the same code signature as this app.
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    private var controller: SPUStandardUpdaterController!

    /// The reminder in the menu for a found update that Sparkle did not show (see `UpdateReminder`).
    private(set) var reminder = UpdateReminder() {
        didSet { if reminder != oldValue { onReminderChange?() } }
    }
    /// Called when `reminder` changes.
    var onReminderChange: (() -> Void)?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Starts the updater: it checks on its schedule (once a day) when automatic checks are on.
    func start() {
        _ = controller
    }

    /// Also brings a found update that the menu reminds of to the front.
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

    // OpenDisplay is a menu bar app without a Dock icon, so it is almost never the active app, and a window for a
    // scheduled update would open behind the app you use. So it uses Sparkle's "gentle" reminders for background apps:
    // Sparkle shows the update window only when it can show it in focus; otherwise the menu shows the update (see
    // `UpdateReminder`), and a click on it brings the window to the front. Sparkle calls these on the main thread.

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                         andInImmediateFocus immediateFocus: Bool) -> Bool {
        UpdateReminder.sparkleShowsScheduledUpdate(immediateFocus: immediateFocus)
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            reminder.willShowUpdate(version: version, shownBySparkle: handleShowingUpdate)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { reminder.userAttended() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { reminder.sessionEnded() }
    }
}

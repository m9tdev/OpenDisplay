/// The reminder in the menu for an update that a scheduled check found.
///
/// OpenDisplay is a menu bar app without a Dock icon, so it is almost never the active app. A window that Sparkle
/// opens for a scheduled check then opens behind the app you use, and you may never see it. So Sparkle shows the
/// window itself only when it can show it in focus (for example just after launch). Otherwise the menu shows an item
/// for the update, and the menu bar icon a dot, until you open the update or the update session ends. These are
/// Sparkle's "gentle scheduled update reminders" for background apps.
public struct UpdateReminder: Equatable, Sendable {
    /// The version of the update that the menu reminds of, `nil` for none.
    public private(set) var version: String?

    public init() {}

    /// Whether Sparkle shows a found scheduled update itself.
    /// - Parameter immediateFocus: Sparkle can show the update in focus now.
    /// - Returns: `false` if the app reminds of the update instead.
    public static func sparkleShowsScheduledUpdate(immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    /// Sparkle is about to show an update, or leaves it to the app.
    /// - Parameters:
    ///   - version: The version of the update, as the user sees it.
    ///   - shownBySparkle: Sparkle shows the update window itself (a check by the user, or a scheduled update in
    ///     focus). Then no reminder is needed.
    public mutating func willShowUpdate(version: String, shownBySparkle: Bool) {
        self.version = shownBySparkle ? nil : version
    }

    /// The user has seen the update window, for example after a click on the reminder.
    public mutating func userAttended() {
        version = nil
    }

    /// The update session ended: the user installed, skipped or dismissed the update.
    public mutating func sessionEnded() {
        version = nil
    }

    /// The title of the menu item, `nil` for no item.
    public var menuTitle: String? {
        version.map { "Update Available: \($0)…" }
    }

    /// The menu bar icon shows a dot.
    public var showsBadge: Bool {
        version != nil
    }
}

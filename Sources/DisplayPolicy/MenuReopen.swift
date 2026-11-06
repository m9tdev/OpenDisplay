/// When the status menu closes and opens again with new items.
///
/// The menu cannot add rows while it is open, so when it needs new rows (a display turns on, a monitor's controls are
/// read, an error appears) or the menu bar icon moved to another screen, it closes and opens again. macOS can also
/// close the menu itself during a display change; then it opens again. A wish to reopen expires after `lifetime`.
public struct MenuReopen: Equatable, Sendable {
    /// How long a wish to reopen lasts, in seconds.
    public static let lifetime: Double = 6

    /// What the menu does at a check.
    public enum Action: Equatable, Sendable {
        /// Nothing now.
        case nothing
        /// Check again a moment later: closing the menu now would interrupt the user.
        case checkAgainLater
        /// Close the open menu and open it again.
        case closeAndOpen
        /// Open the closed menu again.
        case open
    }

    /// When the wish to reopen came, `nil` for none.
    public private(set) var wantedSince: Double?

    public init() {}

    /// The menu needs to reopen: a display turned on or off, or it misses rows.
    /// - Parameter time: Now, in seconds (any clock that only goes forward).
    public mutating func want(at time: Double) {
        wantedSince = time
    }

    /// A check, a moment after `want`, or when the screens change.
    /// - Parameters:
    ///   - time: Now, in seconds, on the same clock as `want`.
    ///   - isOpen: The menu is open.
    ///   - isOutdated: The open menu misses rows, or the menu bar icon is on another screen than the menu.
    ///   - closedByUser: The menu is closed, and the user closed it (a click or a key), not macOS.
    ///   - mouseIsDown: A mouse button is pressed, for example while the user drags a slider in the menu.
    public mutating func check(at time: Double, isOpen: Bool, isOutdated: Bool, closedByUser: Bool,
                               mouseIsDown: Bool) -> Action {
        guard let wantedSince else { return .nothing }
        // Closing the menu now would end the drag, and a resolution slider applies its choice only on mouse up.
        // So wait for the drag to end; the wish starts again then, so a long drag does not let it expire.
        if isOpen, isOutdated, mouseIsDown {
            self.wantedSince = time
            return .checkAgainLater
        }
        guard time - wantedSince < Self.lifetime else {
            self.wantedSince = nil
            return .nothing
        }
        if isOpen {
            guard isOutdated else { return .nothing }
            self.wantedSince = nil
            return .closeAndOpen
        }
        self.wantedSince = nil
        return closedByUser ? .nothing : .open
    }
}

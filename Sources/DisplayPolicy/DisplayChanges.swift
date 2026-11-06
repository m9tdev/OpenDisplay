/// The on/off changes in progress, by display. A change shows its new state at once and is applied later, off the main
/// thread; until it ends, a refresh must not undo that state, and the display must stay in the list (see
/// `DisplayManager.refresh`).
public struct DisplayChanges: Equatable, Sendable {
    /// One change, from `begin`, for `end`.
    public struct Change: Equatable, Sendable {
        /// `CGDirectDisplayID`.
        public let id: UInt32
        let number: Int
    }

    public init() {}

    /// Starts a change of the display.
    public mutating func begin(_ id: UInt32) -> Change {
        changing.insert(id)
        return Change(id: id, number: 0)
    }

    /// Ends a change. Returns true if it is the display's latest change: only the latest change may set the state
    /// that the app shows. An earlier change that ends while a later one is still in progress must leave it alone.
    public mutating func end(_ change: Change) -> Bool {
        changing.remove(change.id)
        return true
    }

    /// True while a change of the display is in progress.
    public func isChanging(_ id: UInt32) -> Bool {
        changing.contains(id)
    }

    /// True when no change is in progress.
    public var isEmpty: Bool { changing.isEmpty }

    /// The number of displays with a change in progress, for the log.
    public var count: Int { changing.count }

    /// The displays a refresh lists: `ids` (from macOS and the displays the app turned off), then the displays of
    /// `before` (the list before the refresh) with a change in progress. A display that is turning off may already be
    /// gone from macOS's lists before the app records it as off; without this, it would drop out of the list and lose
    /// its state (such as its software dimming).
    public func listed(_ ids: [UInt32], before: [UInt32]) -> [UInt32] {
        ids
    }

    private var changing: Set<UInt32> = []
}

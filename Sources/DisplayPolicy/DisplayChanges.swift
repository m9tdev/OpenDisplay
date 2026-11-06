/// The on/off changes in progress, by display. A change shows its new state at once and is applied later, off the main
/// thread; until it ends, a refresh must not undo that state, and the display must stay in the list (see
/// `DisplayManager.refresh`).
///
/// A display can have more than one change in progress: a double-click on its on/off icon turns it off, then on. The
/// display is changing until the last of them ends, and only the latest change may set the state the app shows.
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
        lastNumber += 1
        pending[id, default: []].insert(lastNumber)
        latest[id] = lastNumber
        return Change(id: id, number: lastNumber)
    }

    /// Ends a change. Returns true if it is the display's latest change: only the latest change may set the state
    /// that the app shows. An earlier change that ends while a later one is still in progress must leave it alone.
    /// Ending a change that already ended does nothing, and returns false.
    public mutating func end(_ change: Change) -> Bool {
        let id = change.id
        guard pending[id]?.remove(change.number) != nil else { return false }
        if pending[id]?.isEmpty == true { pending[id] = nil }
        return latest[id] == change.number
    }

    /// True while a change of the display is in progress.
    public func isChanging(_ id: UInt32) -> Bool {
        pending[id] != nil
    }

    /// True when no change is in progress.
    public var isEmpty: Bool { pending.isEmpty }

    /// The number of displays with a change in progress, for the log.
    public var count: Int { pending.count }

    /// The displays a refresh lists: `ids` (from macOS and the displays the app turned off), then the displays of
    /// `before` (the list before the refresh) with a change in progress. A display that is turning off may already be
    /// gone from macOS's lists before the app records it as off; without this, it would drop out of the list and lose
    /// its state (such as its software dimming).
    public func listed(_ ids: [UInt32], before: [UInt32]) -> [UInt32] {
        var listed = ids
        for id in before where isChanging(id) && !listed.contains(id) {
            listed.append(id)
        }
        return listed
    }

    /// The changes in progress, by display.
    private var pending: [UInt32: Set<Int>] = [:]
    /// The number of each display's last change.
    private var latest: [UInt32: Int] = [:]
    private var lastNumber = 0
}

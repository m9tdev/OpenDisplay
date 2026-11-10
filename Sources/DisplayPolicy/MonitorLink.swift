/// The monitor behind a display ID and the DDC connection to it, as a refresh sees them.
///
/// A display ID can stay in the list while the monitor behind it changes: a refresh waits for screen changes to settle,
/// so a monitor unplugged and plugged back (or swapped for another) within that wait can keep its ID. After a wake,
/// or such a replug, macOS can also make a new DDC connection for the same monitor. The state the app keeps for the
/// display (its DDC connection, the values read over it, its software dimming) belongs to the old monitor and
/// connection, so a refresh compares the two links and resets what no longer applies.
public struct MonitorLink: Equatable, Sendable {
    /// Identifies the monitor (vendor, model and serial number, see `DisplayKey`). `nil` when macOS does not report it.
    public var key: String?
    /// The DDC connection. `nil` without DDC.
    public var connection: Connection?

    public init(key: String?, connection: Connection?) {
        self.key = key
        self.connection = connection
    }

    /// A DDC connection, identified by the registry entry ID of its service. `entry` is `nil` when the ID could not be
    /// read: such a connection is never the same as another.
    public struct Connection: Equatable, Sendable {
        public var entry: UInt64?

        public init(entry: UInt64?) {
            self.entry = entry
        }
    }

    /// How the link of a display changed across a refresh.
    public enum Change: Equatable, Sendable {
        /// The same monitor and connection (or still none).
        case same
        /// The same monitor got a DDC connection, or lost it.
        case connectionAppeared
        case connectionLost
        /// The same monitor, over a new DDC connection.
        case connectionReplaced
        /// Another monitor.
        case monitorReplaced
    }

    /// The per-display state a refresh resets.
    public struct Resets: OptionSet, Equatable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Use the DDC connection the refresh found (or none), instead of the one the display had. Answers to reads
        /// sent over the old connection are dropped.
        public static let connection = Resets(rawValue: 1 << 0)
        /// Read the brightness and the volume again now, showing nothing until they answer.
        public static let readValues = Resets(rawValue: 1 << 1)
        /// Keep showing the brightness and the volume, and read them again once the monitor accepts DDC (it may not
        /// right after a wake).
        public static let readValuesWhenReady = Resets(rawValue: 1 << 2)
        /// Apply the shared brightness again, as for a display that turned on: the monitor's level may have changed.
        public static let resync = Resets(rawValue: 1 << 3)
        /// Forget what only the old monitor had: its DDC maximums, capabilities, volume support, mute, contrast,
        /// color preset, input and the monitor settings the calibration reads.
        public static let monitorState = Resets(rawValue: 1 << 4)
        /// Set the software dimming back to 1 and drop the saved color table, without writing it: it is the old
        /// monitor's.
        public static let dimming = Resets(rawValue: 1 << 5)
        /// Previous rule, until the fix: the DDC maximums, reads in flight and capabilities.
        public static let connectionState = Resets(rawValue: 1 << 6)
    }

    /// How the link changed from `old` (before the refresh) to `new` (what the refresh found). A missing key on either
    /// side cannot tell another monitor, so only the connections are compared then.
    public static func change(from old: MonitorLink, to new: MonitorLink) -> Change {
        if let before = old.key, let after = new.key, before != after { return .monitorReplaced }
        switch (old.connection, new.connection) {
        case (nil, nil): return .same
        case (nil, _?): return .connectionAppeared
        case (_?, nil): return .connectionLost
        case let (before?, after?): return before == after ? .same : .connectionReplaced
        }
    }

    /// What a refresh resets for `change`. The same monitor keeps its dimming and what the app knows about it; a new
    /// connection gets its own reads; another monitor starts like a display that just arrived.
    public static func resets(for change: Change) -> Resets {
        switch change {
        case .same: return []
        case .connectionAppeared, .connectionLost: return [.connection, .readValues]
        // Previous rules, until the fix.
        case .connectionReplaced: return [.connection, .readValues, .connectionState]
        case .monitorReplaced: return [.connection, .readValues, .connectionState, .monitorState, .dimming]
        }
    }
}

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
    /// Identifies the DDC connection: the registry entry ID of its service. `nil` without DDC.
    public var connection: UInt64?

    public init(key: String?, connection: UInt64?) {
        self.key = key
        self.connection = connection
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

        /// Use the DDC connection the refresh found (or none), instead of the one the display had.
        public static let connection = Resets(rawValue: 1 << 0)
        /// Read the brightness and the volume again.
        public static let readValues = Resets(rawValue: 1 << 1)
        /// Forget what came over the old connection: the DDC maximums, the reads in flight (their answers are dropped),
        /// and the capabilities (read again).
        public static let connectionState = Resets(rawValue: 1 << 2)
        /// Forget what only the old monitor had: volume support, mute, contrast, color preset, input and the monitor
        /// settings the calibration reads.
        public static let monitorState = Resets(rawValue: 1 << 3)
        /// Set the software dimming back to 1 and drop the saved color table, without writing it: it is the old
        /// monitor's.
        public static let dimming = Resets(rawValue: 1 << 4)
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
    /// connection gets its own reads.
    public static func resets(for change: Change) -> Resets {
        switch change {
        case .same: return []
        case .connectionAppeared, .connectionLost: return [.connection, .readValues]
        case .connectionReplaced: return [.connection, .readValues, .connectionState]
        case .monitorReplaced: return [.connection, .readValues, .connectionState, .monitorState, .dimming]
        }
    }
}

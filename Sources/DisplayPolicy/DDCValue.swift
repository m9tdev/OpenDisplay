/// A value the app sets on a monitor over DDC (brightness, volume, mute), and the app's reads of it.
///
/// Reads and writes go out on one queue per monitor, in order, and the answer to a read comes back later. So a read
/// sent before a write answers with the value from before the write: the app's value is newer, and the read must not
/// undo it.
public struct DDCValue: Equatable, Sendable {
    /// The highest value the monitor accepts, from its answer to a read. nil until a read answers.
    public private(set) var maximum: UInt16?
    /// The maximum a write uses before a read tells the monitor's own. Most monitors use it.
    public static let assumedMaximum: UInt16 = 100

    /// The number of reads sent.
    private var reads = 0
    /// The number of the last read answered.
    private var answered = 0
    /// The number of reads sent before the app's last write: those answer with an older value.
    private var readsBeforeLastWrite = 0
    /// A write that waits for the read in flight, which tells the maximum: the level (0...1).
    private var waiting: Double?

    public init() {}

    /// A read sent to the monitor.
    public struct Read: Equatable, Sendable {
        let number: Int
    }

    /// What to do with the answer to a read.
    public enum Answer: Equatable, Sendable {
        /// Show the monitor's value. `level` is `current` as a part of the maximum, nil if the monitor reports no
        /// maximum.
        case show(current: UInt16, level: Double?)
        /// The monitor did not answer.
        case failed
        /// The app set a newer value since the read was sent: keep the app's value. `failed`: the monitor did not
        /// answer either.
        case outdated(failed: Bool)
    }

    /// Call when a read is sent.
    public mutating func startRead() -> Read {
        reads += 1
        return Read(number: reads)
    }

    /// The value to write for `level` (0...1). nil while the first read is in flight: the write waits for its answer,
    /// which tells the monitor's maximum, and `finish` returns it.
    ///
    /// `outdatesReads`: false for a write the app does not show as its value (the calibration's), so the reads in
    /// flight still answer with the value to show.
    public mutating func set(_ level: Double, outdatesReads: Bool = true) -> UInt16? {
        readsBeforeLastWrite = reads
        if maximum == nil && answered < reads {
            waiting = level
            return nil
        }
        return Self.raw(level, maximum: maximum ?? Self.assumedMaximum)
    }

    /// Call when the app writes a value that has no maximum (mute).
    public mutating func setRaw() {
        readsBeforeLastWrite = reads
    }

    /// Call with the monitor's answer to `read`: its value and maximum, nil if it did not answer.
    /// Returns what to show, and a value to write now, if any.
    public mutating func finish(_ read: Read, current: UInt16?, maximum: UInt16?) -> (answer: Answer, write: UInt16?) {
        answered = max(answered, read.number)
        if let maximum, maximum > 0 { self.maximum = maximum }
        // Without an answer, the write goes out with the usual maximum: many monitors take writes but do not answer reads.
        let write = waiting.map { Self.raw($0, maximum: self.maximum ?? Self.assumedMaximum) }
        // The write goes out now, after the reads sent while it waited: they answer with the value from before it.
        if write != nil { readsBeforeLastWrite = reads }
        waiting = nil
        if read.number <= readsBeforeLastWrite { return (.outdated(failed: current == nil || maximum == nil), write) }
        guard let current, let maximum else { return (.failed, write) }
        return (.show(current: current, level: maximum > 0 ? Double(current) / Double(maximum) : nil), write)
    }

    private static func raw(_ level: Double, maximum: UInt16) -> UInt16 {
        UInt16((min(max(level, 0), 1) * Double(maximum)).rounded())
    }
}

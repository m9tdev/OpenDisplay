/// A value the app sets on a monitor over DDC (brightness, volume, mute), and the app's reads of it.
///
/// Reads and writes go out on one queue per monitor, in order, and the answer to a read comes back later.
public struct DDCValue: Equatable, Sendable {
    /// The highest value the monitor accepts, from its answer to a read. nil until a read answers.
    public private(set) var maximum: UInt16?
    /// The maximum a write uses before a read tells the monitor's own. Most monitors use it.
    public static let assumedMaximum: UInt16 = 100

    private var nextRead = 0

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
    }

    /// Call when a read is sent.
    public mutating func startRead() -> Read {
        nextRead += 1
        return Read(number: nextRead)
    }

    /// The value to write for `level` (0...1).
    public mutating func set(_ level: Double) -> UInt16? {
        Self.raw(level, maximum: maximum ?? Self.assumedMaximum)
    }

    /// Call when the app writes a value that has no maximum (mute).
    public mutating func setRaw() {}

    /// Call with the monitor's answer to `read`: its value and maximum, nil if it did not answer.
    /// Returns what to show, and a value to write now, if any.
    public mutating func finish(_ read: Read, current: UInt16?, maximum: UInt16?) -> (answer: Answer, write: UInt16?) {
        guard let current, let maximum else { return (.failed, nil) }
        if maximum > 0 { self.maximum = maximum }
        return (.show(current: current, level: maximum > 0 ? Double(current) / Double(maximum) : nil), nil)
    }

    private static func raw(_ level: Double, maximum: UInt16) -> UInt16 {
        UInt16((min(max(level, 0), 1) * Double(maximum)).rounded())
    }
}

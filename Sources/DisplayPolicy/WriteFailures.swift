import Foundation

/// Writes to one display that failed in a row, and the error the menu shows under the display for them.
///
/// A DDC write is never acknowledged by the monitor, so a failed DDC write is a failed transport: the connection to the
/// monitor is gone or does not work. One failure can be a monitor that wakes up, so the error shows after a few in a
/// row. The next write that works clears it.
public struct WriteFailures: Equatable, Sendable {
    /// DDC writes that fail in a row before the display shows as not responding.
    public static let ddcThreshold = 3
    public static let ddcMessage = "Not responding over DDC"
    public static let builtinMessage = "Could not set the brightness"

    /// For the DDC writes over one connection to an external display.
    public static let ddc = WriteFailures(threshold: ddcThreshold, message: ddcMessage)
    /// For the brightness writes to the built-in display: macOS refused the level, so the slider shows a brightness
    /// the display does not have.
    public static let builtin = WriteFailures(threshold: 1, message: builtinMessage)

    /// Failures in a row before the error shows.
    public let threshold: Int
    public let message: String
    /// The writes that failed since the last one that worked.
    public private(set) var inARow = 0

    public init(threshold: Int, message: String) {
        self.threshold = max(threshold, 1)
        self.message = message
    }

    /// The error to show, nil if none.
    public var error: String? {
        inARow >= threshold ? message : nil
    }

    /// Counts one write.
    /// - Returns: True if `error` changed, so the caller updates the menu and logs it once, not at every write.
    @discardableResult
    public mutating func record(succeeded: Bool) -> Bool {
        let before = error
        inARow = succeeded ? 0 : inARow + 1
        return error != before
    }

    /// Counts one DDC read: one that works shows that the transport works, like a write that works. A failed read
    /// counts nothing, since reads also fail when the monitor is slow to answer.
    /// - Returns: True if `error` changed.
    @discardableResult
    public mutating func recordRead(succeeded: Bool) -> Bool {
        succeeded ? record(succeeded: true) : false
    }

    /// Starts the count again, for example after a wake: writes to a monitor that slept can fail.
    /// - Returns: True if `error` changed.
    @discardableResult
    public mutating func reset() -> Bool {
        let before = error
        inARow = 0
        return error != before
    }
}

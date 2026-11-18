import Foundation

/// Where an error the menu shows comes from. Each source sets and clears only its own error.
/// The order of the cases is the order in the menu.
public enum ErrorSource: Hashable, Comparable, Sendable {
    /// Keeping a display on: a failed attempt to turn a display on again after the last one went away. First in the
    /// menu: the Mac may have no screen.
    case restore
    /// The brightness calibration: a setting it turned off for the comparison (automatic brightness, True Tone) that it
    /// could not turn back on.
    case calibration
    /// A change of one display from the menu: turning it on or off, its display mode or rotation, or making it the
    /// main display. The result of the latest change of that display, so a change of another display keeps it. The
    /// displays show in the order of their ids.
    case display(UInt32)
    /// Applying a preset: the result of the latest one.
    case preset
}

/// The errors the menu shows, one per source, so one source cannot clear or replace the error of another.
public struct ErrorSlots: Equatable, Sendable {
    private var slots: [ErrorSource: String] = [:]

    public init() {}

    /// The error of `source`, nil if none.
    public subscript(source: ErrorSource) -> String? {
        get { slots[source] }
        set { slots[source] = newValue }
    }

    /// All errors as one text, in the order of `ErrorSource`, nil if there is none.
    public var text: String? {
        let messages = slots.sorted { $0.key < $1.key }.map(\.value)
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    /// A change of display `id` starts: the error of its earlier change goes. The errors about other displays, and
    /// the errors of the other sources, stay.
    public mutating func startChange(of id: UInt32) {
        slots[.display(id)] = nil
    }

    /// Clears every error, for example when the user has seen them.
    public mutating func removeAll() {
        slots = [:]
    }
}

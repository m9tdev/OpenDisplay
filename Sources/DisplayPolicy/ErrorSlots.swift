import Foundation

/// Where an error the menu shows comes from. Each source sets and clears only its own error.
/// The order of the cases is the order in the menu.
public enum ErrorSource: Hashable, Comparable, Sendable {
    /// Keeping a display on: a failed attempt to turn a display on again after the last one went away. First in the
    /// menu: the Mac may have no screen.
    case restore
    /// Turning a display on or off from the menu, display mode and arrangement changes, and presets: the result of the
    /// latest one.
    case action
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

    /// Clears every error, for example when the user has seen them.
    public mutating func removeAll() {
        slots = [:]
    }
}

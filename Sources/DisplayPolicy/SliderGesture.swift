/// A press, drag and release on a slider in the menu, and what the slider does at each step.
///
/// AppKit sends a slider's action at mouse-down too: once with the old value, then with the clicked one. So a click
/// on the track is not a finished choice. Keyboard and VoiceOver changes come without a gesture (`idle`).
public enum SliderGesture: Equatable, Sendable {
    /// No gesture.
    case idle
    /// The mouse went down when the slider was at `value`, and the knob has not moved yet.
    case pressed(at: Double)
    /// The knob moved since the mouse went down, and the mouse is still down.
    case dragging
    /// The mouse went up. The gesture ends after this step.
    case released

    /// The slider is at `value` now. Returns whether it is a new value: the old value that AppKit sends again at
    /// mouse-down is not.
    public mutating func moved(to value: Double) -> Bool {
        switch self {
        case .pressed(let start):
            guard value != start else { return false }
            self = .dragging
            return true
        case .idle, .dragging, .released:
            return true
        }
    }

    /// Whether the knob shows the stored value. Not while the user holds it: it would jump away from the mouse.
    public var followsStoredValue: Bool {
        switch self {
        case .idle, .released: true
        case .pressed, .dragging: false
        }
    }

    /// The choice a stepped slider (a resolution, a refresh rate) applies when it is at `index`, or `nil`.
    /// A choice blanks the screen for a moment, so only a finished choice applies, and only a new one.
    public func choice(_ index: Int, current: Int?) -> Int? {
        switch self {
        case .pressed, .dragging: nil
        case .idle, .released: index == current ? nil : index
        }
    }
}

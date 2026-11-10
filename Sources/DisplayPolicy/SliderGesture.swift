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

    /// The slider is at `value` now. Returns whether it is a new value.
    public mutating func moved(to value: Double) -> Bool {
        switch self {
        case .pressed, .idle, .dragging, .released:
            return true
        }
    }

    /// Whether the knob shows the stored value.
    public var followsStoredValue: Bool {
        switch self {
        case .idle, .released, .pressed: true
        case .dragging: false
        }
    }

    /// The choice a stepped slider (a resolution, a refresh rate) applies when it is at `index`, or `nil`.
    public func choice(_ index: Int, current: Int?) -> Int? {
        switch self {
        case .dragging: nil
        case .idle, .released, .pressed: index
        }
    }
}

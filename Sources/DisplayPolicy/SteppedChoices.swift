/// The choices a stepped slider (a resolution, a refresh rate) shows, and the index of the current one.
///
/// A refresh can bring a new list while the user holds the knob. The knob then still shows a title of the old list, so
/// the slider keeps the old list until the gesture ends: the release applies the choice the knob shows.
public struct SteppedChoices<Choice> {
    public private(set) var choices: [Choice] = []
    public private(set) var current: Int?

    public init() {}

    /// Takes a new list, unless the user holds the knob. Returns whether it took it, so the slider shows it.
    @discardableResult
    public mutating func update(_ choices: [Choice], current: Int?, gesture: SliderGesture) -> Bool {
        guard gesture.followsStoredValue else { return false }
        self.choices = choices
        self.current = current
        return true
    }

    /// The choice to apply with the knob at `index`, or `nil` (see `SliderGesture.choice`).
    public func choice(at index: Int, gesture: SliderGesture) -> Choice? {
        guard let index = gesture.choice(index, current: current), choices.indices.contains(index) else { return nil }
        return choices[index]
    }
}

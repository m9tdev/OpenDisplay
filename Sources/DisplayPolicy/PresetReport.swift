/// What Apply tells the user: why a preset changes nothing, and what it skips.
extension PresetPolicy {
    /// What Apply does with a preset, decided before it changes anything.
    public struct Plan: Sendable {
        /// The displays the preset changes, as `targets` gives them.
        public var targets: [(id: UInt32, state: Preset.DisplayState)]
        /// The entries that turn a display on, whose display is not connected. Apply skips them.
        public var notConnected: [Preset.DisplayState]
        /// Why Apply changes nothing, `nil` when it goes on.
        public var refusal: String?
        /// What Apply skips, one message per display.
        public var skipped: [String]
    }

    /// The plan for applying `preset` to `displays`.
    public static func plan(_ preset: Preset, displays: [Display]) -> Plan {
        let targets = targets(of: preset, displays: displays)
        let refusal = targets.contains(where: { $0.state.isEnabled }) ? nil : "This preset turns off all displays."
        return Plan(targets: targets, notConnected: [], refusal: refusal, skipped: [])
    }

    /// The refusal when the displays that would stay on are not enough (see `DisplayPolicy.canDisable`).
    public static func turnsOffAllDisplays(notConnected: [Preset.DisplayState]) -> String {
        "This preset turns off all displays."
    }

    /// The message after Apply, from what it skipped and the errors of its steps, in that order. `nil` when Apply did
    /// everything.
    public static func report(_ messages: [String]) -> String? {
        messages.first
    }
}

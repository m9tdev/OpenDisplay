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

    /// The plan for applying `preset` to `displays`. An entry that turns a display off, whose display is not
    /// connected, is not reported: the display is not on, as the preset wants.
    public static func plan(_ preset: Preset, displays: [Display]) -> Plan {
        let targets = targets(of: preset, displays: displays)
        // The entries without a display: those that `targets` left out. Equal entries are interchangeable here.
        var missing = preset.displays
        for (_, state) in targets {
            if let index = missing.firstIndex(of: state) { missing.remove(at: index) }
        }
        let notConnected = missing.filter(\.isEnabled)

        var refusal: String?
        if !targets.contains(where: { $0.state.isEnabled }) {
            refusal = targets.isEmpty && !notConnected.isEmpty
                ? "Nothing changed: \(isNotConnected(notConnected))."
                : turnsOffAllDisplays(notConnected: notConnected)
        }
        return Plan(targets: targets, notConnected: notConnected, refusal: refusal,
                    skipped: notConnected.map { "Skipped \($0.name): not connected." })
    }

    /// The refusal when no display would stay on (see also `DisplayPolicy.canDisable`). When the preset turns on a
    /// display that is not connected, that is the reason, so it says so.
    public static func turnsOffAllDisplays(notConnected: [Preset.DisplayState]) -> String {
        guard !notConnected.isEmpty else { return "This preset turns off all displays." }
        return "Nothing changed: \(isNotConnected(notConnected)), and this preset turns off the other displays."
    }

    /// The message when Apply skips the resolution of a display, because the display does not have that mode now
    /// (for example after a firmware or cable change).
    public static func resolutionNotAvailable(_ state: Preset.DisplayState) -> String {
        let hiDPI = state.pixelWidth > state.width ? " HiDPI" : ""
        let rate = state.refreshRate == state.refreshRate.rounded()
            ? "\(Int(state.refreshRate))" : "\((state.refreshRate * 100).rounded() / 100)"
        return "Skipped the resolution of \(state.name): \(state.width) × \(state.height)\(hiDPI) at \(rate) Hz is not available."
    }

    /// The message after Apply, from what it skipped and the errors of its steps, in that order. `nil` when Apply did
    /// everything.
    public static func report(_ messages: [String]) -> String? {
        messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    /// The message Settings shows for Apply. Apply finishes later, so its result comes in a callback: each Apply gets a
    /// run number from `start`, and passes it to `finish`.
    public struct ApplyMessage: Equatable, Sendable {
        /// The message to show, `nil` for none.
        public private(set) var text: String?
        private var run = 0

        public init() {}

        /// An Apply starts: the old message goes. Returns the number of this run.
        public mutating func start() -> Int {
            run += 1
            text = nil
            return run
        }

        /// An Apply finished with `message`.
        public mutating func finish(_ run: Int, message: String?) {
            text = message
        }

        /// The window closed: its message goes.
        public mutating func close() {
            text = nil
        }

        /// Another action (Save) makes the message old.
        public mutating func clear() {
            text = nil
        }
    }

    /// "Dell is not connected", "Dell and LG are not connected".
    private static func isNotConnected(_ states: [Preset.DisplayState]) -> String {
        let names = states.map(\.name)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "\(list) \(names.count == 1 ? "is" : "are") not connected"
    }
}

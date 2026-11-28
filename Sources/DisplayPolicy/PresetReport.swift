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
                    skipped: uniqueNames(notConnected).map { "Skipped \($0): not connected." })
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

    /// The results of Apply's steps, by display. The first failure of a display is its error: a later step of the
    /// same display that fails adds nothing (a display that did not turn on cannot change its resolution either, and
    /// the first error tells why).
    public struct StepResults: Equatable, Sendable {
        /// The displays that failed, in the order of their first failure, with that failure.
        private var failures: [(id: UInt32, error: String)] = []

        public init() {}

        /// A step of display `id` worked (`nil`) or failed with `error`.
        public mutating func record(_ id: UInt32, error: String?) {
            guard let error, !failed(id) else { return }
            failures.append((id, error))
        }

        /// True when a step of display `id` failed.
        public func failed(_ id: UInt32) -> Bool {
            failures.contains { $0.id == id }
        }

        /// One error per failed display, in the order they failed.
        public var errors: [String] { failures.map(\.error) }

        public static func == (lhs: StepResults, rhs: StepResults) -> Bool {
            lhs.failures.elementsEqual(rhs.failures) { $0.id == $1.id && $0.error == $1.error }
        }
    }

    /// Turns on the displays of `targets` that the preset wants on and that are off now, the first step of Apply.
    /// `turnOn` applies it to a display (its ID and name) and returns its error (nil: macOS accepted it), and
    /// `isActive` tells if a display is on: it is read before, to skip a display that is on already, and again right
    /// after `turnOn`. As for the menu and the safety net, a display that macOS accepted but that is not on did not
    /// turn on (see `DisplayPolicy.turnOnError`): that is its error, not the later steps it then fails too.
    /// `builtins`: the built-in displays, for the wording of that error.
    public static func turnOn(_ targets: [(id: UInt32, state: Preset.DisplayState)], builtins: Set<UInt32>,
                              turnOn: (UInt32, String) -> String?,
                              isActive: (UInt32) -> Bool) -> StepResults {
        var results = StepResults()
        for (id, state) in targets where state.isEnabled && !isActive(id) {
            let applied = turnOn(id, state.name)
            results.record(id, error: DisplayPolicy.turnOnError(applied, isActive: isActive(id), name: state.name,
                                                                isBuiltin: builtins.contains(id)))
        }
        return results
    }

    /// The message after Apply: what it skipped, then one error per display that failed. `nil` when Apply did
    /// everything.
    public static func report(skipped: [String], results: StepResults) -> String? {
        let messages = skipped + results.errors
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    /// The message Settings shows for Apply, and whether an Apply is still running. Apply finishes later, so its
    /// result comes in a callback: each Apply gets a run number from `start`, and passes it to `finish`.
    ///
    /// ```
    /// idle ──start──▶ applying(run) ──finish(run, message)──▶ showing(message), or idle without a message
    ///                   │  ▲ start: a newer run replaces it
    ///                   └──┴─ clear: stays applying, so its result still shows
    /// showing ──clear──▶ idle            any phase ──close──▶ idle (the runs still going are dropped)
    /// ```
    public struct ApplyMessage: Equatable, Sendable {
        public enum Phase: Equatable, Sendable {
            /// No Apply is running, and there is no message.
            case idle
            /// Apply `run` is running. A message shows only once it finishes.
            case applying(run: Int)
            /// The last Apply finished with this message.
            case showing(String)
        }

        public private(set) var phase: Phase = .idle
        /// The number of the last run handed out. Runs that were replaced or dropped keep their old numbers, so their
        /// results never match the run of `applying`.
        private var lastRun = 0

        public init() {}

        /// The message to show, `nil` for none.
        public var text: String? {
            if case .showing(let message) = phase { return message }
            return nil
        }

        /// An Apply starts: the old message goes, and so does the result of the run still going. Returns the number
        /// of this run.
        public mutating func start() -> Int {
            lastRun += 1
            phase = .applying(run: lastRun)
            return lastRun
        }

        /// An Apply finished with `message`, `nil` when it did everything. Ignored unless it is the run that is
        /// applying: another Apply started since, or the window closed.
        public mutating func finish(_ run: Int, message: String?) {
            guard phase == .applying(run: run) else { return }
            phase = message.map(Phase.showing) ?? .idle
        }

        /// The window closed: its message goes, and so do the results of the runs still going.
        public mutating func close() {
            phase = .idle
        }

        /// Another action (Save) makes the message old. A run still going is kept: its result shows when it finishes.
        public mutating func clear() {
            if case .showing = phase { phase = .idle }
        }
    }

    /// The names of `states`, each once: two displays of the same model have the same name.
    private static func uniqueNames(_ states: [Preset.DisplayState]) -> [String] {
        var names: [String] = []
        for state in states where !names.contains(state.name) { names.append(state.name) }
        return names
    }

    /// "Dell is not connected", "Dell and LG are not connected".
    private static func isNotConnected(_ states: [Preset.DisplayState]) -> String {
        let names = uniqueNames(states)
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "\(list) \(names.count == 1 ? "is" : "are") not connected"
    }
}

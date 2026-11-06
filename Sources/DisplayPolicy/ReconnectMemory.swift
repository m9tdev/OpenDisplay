/// What a display gets back when it returns after it went away: its monitor was turned off with its power button,
/// unplugged, or switched to another input. macOS then drops the display from its lists and resets its color table,
/// and the app makes a new display object when it returns. Without this memory, a display dimmed in software comes
/// back brighter, and a synced display does not follow the built-in display until the built-in brightness changes.
public struct ReconnectMemory: Equatable, Sendable {
    /// The software dimming (below 1) of the displays that went away, by key.
    private var dimming: [String: Double] = [:]

    public init() {}

    /// The lowest software dimming that a display gets back when it turns on. A display dimmed to black, or almost,
    /// would look dead.
    public static let minimumRestoredDimming = 0.05

    /// A display in the app's list, before or after a refresh.
    public struct Snapshot: Equatable, Sendable {
        /// `CGDirectDisplayID`.
        public var id: UInt32
        /// Identifies the display across reconnects, from the last time it was on. nil if it never was on.
        public var key: String?
        public var isEnabled: Bool
        /// Software dimming: 1 is the normal image.
        public var dimming: Double
        /// It follows the built-in display's brightness.
        public var isSynced: Bool

        public init(id: UInt32, key: String?, isEnabled: Bool, dimming: Double = 1, isSynced: Bool = false) {
            self.id = id
            self.key = key
            self.isEnabled = isEnabled
            self.dimming = dimming
            self.isSynced = isSynced
        }
    }

    /// What the app does after a refresh.
    public struct Plan: Equatable, Sendable {
        /// The new software dimming of displays that turned on.
        public var dimming: [UInt32: Double]
        /// Apply the shared brightness to the synced displays again.
        public var resyncsBrightness: Bool

        public init(dimming: [UInt32: Double] = [:], resyncsBrightness: Bool = false) {
            self.dimming = dimming
            self.resyncsBrightness = resyncsBrightness
        }
    }

    /// Call on each refresh of the display list. `before`: the list before the refresh; `after`: the list after it;
    /// `turnedOnByApp`: the displays that the app turned on since the last refresh.
    ///
    /// A display missing from `after` went away: its dimming is remembered. A display new in `after` gets back the
    /// dimming it had when it went away.
    ///
    /// The shared brightness is applied again when a synced display turned on: new in the list, off before the
    /// refresh, or turned on by the app. The app marks a display as on as soon as it turns it on, so the lists alone do
    /// not show that change. The display's level may have changed while it was away or off (for example, another
    /// computer on another input), and the built-in brightness did not change, so nothing else syncs it.
    public mutating func refresh(before: [Snapshot], after: [Snapshot], turnedOnByApp: Set<UInt32>) -> Plan {
        let previous = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remaining = Set(after.map(\.id))
        for display in before where !remaining.contains(display.id) {
            if let key = display.key {
                dimming[key] = display.dimming < 1 ? display.dimming : nil
            }
        }
        var plan = Plan()
        for display in after where display.isEnabled {
            let old = previous[display.id]
            if old == nil, let key = display.key {
                plan.dimming[display.id] = dimming.removeValue(forKey: key) ?? 1
            }
            if display.isSynced && (old?.isEnabled != true || turnedOnByApp.contains(display.id)) {
                plan.resyncsBrightness = true
            }
        }
        return plan
    }
}

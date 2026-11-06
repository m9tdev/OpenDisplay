/// What a display gets back when it returns after it went away: its monitor was turned off with its power button,
/// unplugged, or switched to another input. macOS then drops the display from its lists and resets its color table,
/// and the app makes a new display object when it returns. Without this memory, a display dimmed in software comes
/// back brighter, and a synced display does not follow the built-in display until the built-in brightness changes.
public struct ReconnectMemory: Equatable, Sendable {
    /// The software dimming (below 1) of the displays that went away, by key.
    private var dimming: [String: Double] = [:]

    public init() {}

    /// A display went away. `key` identifies it across reconnects (taken while it was on; nil if it never was), and
    /// `dimming` is its software dimming (1 is the normal image).
    public mutating func displayLeft(key: String?, dimming: Double) {
        guard let key else { return }
        self.dimming[key] = dimming < 1 ? dimming : nil
    }

    /// The software dimming for a display that returns as a new display object: what it had when it went away, or 1.
    /// Given once: from then on, the display object holds it.
    public mutating func displayReturned(key: String) -> Double {
        dimming.removeValue(forKey: key) ?? 1
    }

    /// A display after a refresh, for `resyncsBrightness`.
    public struct RefreshedDisplay: Equatable, Sendable {
        /// Before the refresh: nil if it was not in the list (new, or it went away and came back).
        public var wasEnabled: Bool?
        public var isEnabled: Bool
        /// It follows the built-in display's brightness.
        public var isSynced: Bool

        public init(wasEnabled: Bool?, isEnabled: Bool, isSynced: Bool) {
            self.wasEnabled = wasEnabled
            self.isEnabled = isEnabled
            self.isSynced = isSynced
        }
    }

    /// True if the shared brightness must be applied again to the synced displays after a refresh: a synced display
    /// turned on, as a new display or one that was off. Its level may have changed while it was away (for example,
    /// another computer on another input), and the built-in brightness did not change, so nothing else syncs it.
    public static func resyncsBrightness(_ displays: [RefreshedDisplay]) -> Bool {
        displays.contains { $0.isSynced && $0.isEnabled && $0.wasEnabled != true }
    }
}

/// What a display gets back when it returns after it went away: its monitor was turned off with its power button,
/// unplugged, or switched to another input. macOS then drops the display from its lists and resets its color table,
/// and the app makes a new display object when it returns.
public struct ReconnectMemory: Equatable, Sendable {
    public init() {}

    /// A display went away. `key` identifies it across reconnects (taken while it was on; nil if it never was), and
    /// `dimming` is its software dimming (1 is the normal image).
    public mutating func displayLeft(key: String?, dimming: Double) {}

    /// The software dimming for a display that returns as a new display object.
    public mutating func displayReturned(key: String) -> Double {
        1
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

    /// True if the shared brightness must be applied again to the synced displays after a refresh.
    public static func resyncsBrightness(_ displays: [RefreshedDisplay]) -> Bool {
        false
    }
}

/// The state of one display, for the on/off decisions. Plain values, so the decisions can be tested without displays.
public struct DisplayState: Equatable, Sendable {
    /// `CGDirectDisplayID`.
    public var id: UInt32
    public var isBuiltin: Bool
    /// Connected (in `CGGetOnlineDisplayList`).
    public var isOnline: Bool
    /// On (in `CGGetActiveDisplayList`).
    public var isActive: Bool
    /// Not a real screen: for example the placeholder that macOS makes when no display is on.
    public var isVirtual: Bool
    /// OpenDisplay turned it off.
    public var isDisabledByUs: Bool

    public init(id: UInt32, isBuiltin: Bool = false, isOnline: Bool = true, isActive: Bool = true,
                isVirtual: Bool = false, isDisabledByUs: Bool = false) {
        self.id = id
        self.isBuiltin = isBuiltin
        self.isOnline = isOnline
        self.isActive = isActive
        self.isVirtual = isVirtual
        self.isDisabledByUs = isDisabledByUs
    }
}

/// When a display may turn off, and which display to turn on again.
public enum DisplayPolicy {
    /// True for a display that is not a real screen, from its `CGDisplayVendorNumber` and `CGDisplayModelNumber`.
    public static func isVirtual(vendor: UInt32, model: UInt32, isBuiltin: Bool) -> Bool {
        false
    }

    /// True if turning off the displays `ids` leaves a display on.
    public static func canDisable(_ ids: Set<UInt32>, in displays: [DisplayState]) -> Bool {
        displays.contains { $0.isActive && !ids.contains($0.id) }
    }

    /// The displays to try to turn on again, in order, because no display is on. Empty if nothing needs to change.
    public static func displaysToRestore(in displays: [DisplayState]) -> [UInt32] {
        []
    }
}

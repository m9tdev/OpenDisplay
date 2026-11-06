/// The stable key of a display: its vendor, model and serial number, which stay the same across reconnects and app
/// restarts (the display ID can change).
public enum DisplayKey {
    /// The key from what macOS reports: `CGDisplayVendorNumber`, `CGDisplayModelNumber` and `CGDisplaySerialNumber`.
    /// `nil` when macOS does not know the display ID now: it then reports 0xFFFFFFFF.
    public static func key(vendor: UInt32, model: UInt32, serial: UInt32) -> String? {
        guard vendor != unknown, model != unknown else { return nil }
        return "\(vendor)-\(model)-\(serial)"
    }

    /// What macOS reports for a display ID it does not know.
    static let unknown = UInt32.max

    /// The key of a display: what macOS reports, or, while macOS does not know the display (it may be off), the key
    /// remembered from when it was on. `nil` when there is neither.
    public static func key(reported: String?, remembered: String?) -> String? {
        reported ?? remembered
    }

    /// The remembered keys, by display ID, after macOS reported `reported` for the displays that are on: a key
    /// replaces the remembered one (the ID may now belong to another display), and `nil` keeps it.
    public static func remembered(_ keys: [UInt32: String], reported: [UInt32: String?]) -> [UInt32: String] {
        var keys = keys
        for case let (id, key?) in reported {
            keys[id] = key
        }
        return keys
    }
}

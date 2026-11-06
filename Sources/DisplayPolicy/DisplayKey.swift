/// The stable key of a display: its vendor, model and serial number, which stay the same across reconnects and app
/// restarts (the display ID can change).
public enum DisplayKey {
    /// The key from what macOS reports: `CGDisplayVendorNumber`, `CGDisplayModelNumber` and `CGDisplaySerialNumber`.
    /// `nil` when macOS does not know the display ID now: it then reports 0xFFFFFFFF as vendor and model. A known
    /// vendor and model with the serial number 0xFFFFFFFF still give a key, as in earlier versions: saved presets and
    /// settings use it.
    public static func key(vendor: UInt32, model: UInt32, serial: UInt32) -> String? {
        guard vendor != unknown, model != unknown else { return nil }
        return "\(vendor)-\(model)-\(serial)"
    }

    /// What macOS reports for a display ID it does not know.
    static let unknown = UInt32.max

    /// The key of a display: the key remembered from when it was last on, or, without one, what macOS reports.
    /// `nil` when there is neither. The remembered key comes first: while a display is off, macOS may not know it, or
    /// may report another key (for example without the serial number). For a display that is on, the two are the
    /// same, because each refresh remembers the key macOS reports.
    public static func key(reported: String?, remembered: String?) -> String? {
        remembered ?? reported
    }

    /// The remembered keys, by display ID, after macOS reported `reported` for the displays that are on: a key
    /// replaces the remembered one (the ID may now belong to another display), and `nil` keeps it. Only the displays
    /// in `reported` and `keeping` (the displays the app still lists, such as the ones it turned off) stay remembered.
    public static func remembered(_ keys: [UInt32: String], reported: [UInt32: String?],
                                  keeping: Set<UInt32>) -> [UInt32: String] {
        var keys = keys.filter { keeping.contains($0.key) || reported.keys.contains($0.key) }
        for case let (id, key?) in reported {
            keys[id] = key
        }
        return keys
    }

    /// The keys that per-display settings are saved by (brightness sync, expanded menu rows, software dimming), by
    /// display ID. `known`: the key of each display (see `key(reported:remembered:)`); `previous`: what this returned
    /// last time, saved across app restarts.
    ///
    /// Two monitors of the same model without a serial number have the same key, so each display ID gets its own
    /// settings key: a display keeps the one it had (`previous`), else it gets its key, or, while another display has
    /// that key, its key with its display ID. So settings saved under the key by earlier versions stay with one display
    /// (the one with the lowest ID, when both are new). The keys of displays that are not in `known` stay, so a twin
    /// that goes away gets its own settings back when it returns, but its plain key goes to a display with that key and
    /// no settings key yet (for example the same monitor with a new display ID).
    public static func settingsKeys(_ known: [UInt32: String], previous: [UInt32: String]) -> [UInt32: String] {
        var keys = previous
        // A display ID now used by a monitor of another model, or a settings key claimed twice: drop it.
        var claimed: Set<String> = []
        for id in known.keys.sorted() {
            guard let key = keys[id] else { continue }
            if isSettingsKey(key, of: known[id]!) && !claimed.contains(key) {
                claimed.insert(key)
            } else {
                keys[id] = nil
            }
        }
        for id in known.keys.sorted() where keys[id] == nil {
            let base = known[id]!
            let key = claimed.contains(base) ? "\(base)#\(id)" : base
            // Each settings key names one display: a display that is gone loses it.
            for (other, value) in keys where value == key {
                keys[other] = nil
            }
            keys[id] = key
            claimed.insert(key)
        }
        return keys
    }

    /// True when `settingsKey` can belong to a display with `key`: it is the key, or the key with a display ID.
    static func isSettingsKey(_ settingsKey: String, of key: String) -> Bool {
        settingsKey == key || settingsKey.hasPrefix(key + "#")
    }
}

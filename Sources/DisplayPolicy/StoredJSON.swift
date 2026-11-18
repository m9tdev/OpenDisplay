import Foundation

/// Values saved as JSON in the user defaults.
public enum StoredJSON {
    /// Saves `value` as JSON under `key`. If it cannot be encoded (JSON has no infinite numbers, for example), keeps
    /// what is saved and returns false: saving nothing would wipe it.
    @discardableResult
    public static func save<T: Encodable>(_ value: T, forKey key: String, in defaults: UserDefaults = .standard) -> Bool {
        guard let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// Reads the value saved as JSON under `key`, or nil if there is none or it cannot be decoded.
    ///
    /// Saved data that cannot be decoded (for example from a newer version of the app, in another format) is moved to
    /// a backup key of its own, so that the next save does not write over it.
    /// - Returns: The value, and the key the saved data was moved to, if it was.
    public static func load<T: Decodable>(_ type: T.Type, forKey key: String, in defaults: UserDefaults = .standard,
                                          date: Date = Date()) -> (value: T?, backupKey: String?) {
        guard let data = defaults.data(forKey: key) else { return (nil, nil) }
        if let value = try? JSONDecoder().decode(T.self, from: data) { return (value, nil) }
        let backupKey = backUp(data, of: key, in: defaults, date: date)
        defaults.removeObject(forKey: key)
        return (nil, backupKey)
    }

    /// Reads a dictionary saved as JSON under `key`, entry by entry: an entry that cannot be decoded is left out, and
    /// the others are kept.
    ///
    /// If an entry or the whole dictionary cannot be decoded, all the saved data is copied to a backup key of its own
    /// (see `load`), and only the entries that could be read stay under `key`.
    /// - Returns: The entries, and the key the saved data was copied to, if it was.
    public static func loadEntries<T: Codable>(_ type: T.Type, forKey key: String,
                                               in defaults: UserDefaults = .standard,
                                               date: Date = Date()) -> (value: [String: T], backupKey: String?) {
        guard let data = defaults.data(forKey: key) else { return ([:], nil) }
        guard let entries = try? JSONDecoder().decode([String: Entry<T>].self, from: data) else {
            let backupKey = backUp(data, of: key, in: defaults, date: date)
            defaults.removeObject(forKey: key)
            return ([:], backupKey)
        }
        let value = entries.compactMapValues(\.value)
        guard value.count < entries.count else { return (value, nil) }
        let backupKey = backUp(data, of: key, in: defaults, date: date)
        // So the next load does not make another backup.
        save(value, forKey: key, in: defaults)
        return (value, backupKey)
    }

    /// An entry of a dictionary, nil if it cannot be decoded.
    private struct Entry<T: Decodable>: Decodable {
        let value: T?

        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    /// Saves `data` under a new key, "<key>.unreadable-<date>" (the date in seconds since 1970), with a number added if
    /// that key is taken.
    private static func backUp(_ data: Data, of key: String, in defaults: UserDefaults, date: Date) -> String {
        let base = "\(key).unreadable-\(Int(date.timeIntervalSince1970))"
        var backupKey = base
        var number = 1
        while defaults.object(forKey: backupKey) != nil {
            number += 1
            backupKey = "\(base)-\(number)"
        }
        defaults.set(data, forKey: backupKey)
        return backupKey
    }
}

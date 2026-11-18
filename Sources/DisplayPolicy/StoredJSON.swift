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
    /// - Returns: The value, and the key the saved data was moved to, if it was.
    public static func load<T: Decodable>(_ type: T.Type, forKey key: String, in defaults: UserDefaults = .standard,
                                          date: Date = Date()) -> (value: T?, backupKey: String?) {
        guard let data = defaults.data(forKey: key) else { return (nil, nil) }
        return (try? JSONDecoder().decode(T.self, from: data), nil)
    }

    /// Reads a dictionary saved as JSON under `key`.
    /// - Returns: The entries, and the key the saved data was moved to, if it was.
    public static func loadEntries<T: Decodable>(_ type: T.Type, forKey key: String,
                                                 in defaults: UserDefaults = .standard,
                                                 date: Date = Date()) -> (value: [String: T], backupKey: String?) {
        let (value, backupKey) = load([String: T].self, forKey: key, in: defaults, date: date)
        return (value ?? [:], backupKey)
    }
}

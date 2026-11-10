import Foundation

/// Values saved as JSON in the user defaults.
public enum StoredJSON {
    /// Saves `value` as JSON under `key`.
    public static func save<T: Encodable>(_ value: T, forKey key: String, in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

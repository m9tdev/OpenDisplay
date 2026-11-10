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
}

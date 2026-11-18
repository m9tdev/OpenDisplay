/// Window notifications (a window becomes key, a window closes) come for every window of the app. A view of one
/// window acts only on those about its own window.
public enum WindowNotification {
    /// Whether a notification whose object is `object` is about `window`. Nothing is about a window that does not
    /// exist yet, and a notification without a window is about none (`===` alone is true for two `nil`s).
    public static func isAbout(_ object: AnyObject?, window: AnyObject?) -> Bool {
        guard let object, let window else { return false }
        return object === window
    }
}

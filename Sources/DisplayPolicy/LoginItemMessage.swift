/// The Launch at Login error that Settings shows.
///
/// Turning the login item on or off can fail, for example when the app is not in Applications or needs approval.
/// The user can then fix it in System Settings, so the status is checked again (each second, when Settings is shown,
/// and when the app becomes active), and the error goes once the login item is as the user wanted.
public struct LoginItemMessage: Equatable, Sendable {
    /// The message to show, `nil` for none.
    public private(set) var text: String?
    /// What the user asked for when it failed: on (`true`) or off.
    private var wanted: Bool?

    public init() {}

    /// Turning the login item on (`wanted` true) or off failed with `message`.
    public mutating func failed(wanted: Bool, message: String) {
        self.wanted = wanted
        text = message
    }

    /// Turning the login item on or off worked.
    public mutating func succeeded() {
        wanted = nil
        text = nil
    }

    /// The status was checked again: the login item is on (`isEnabled`) or not.
    public mutating func checked(isEnabled: Bool) {
        guard let wanted, isEnabled == wanted else { return }
        self.wanted = nil
        text = nil
    }
}

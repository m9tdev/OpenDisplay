/// The displays OpenDisplay turned off ("marks"), with their names, and the login session each mark was made in.
///
/// The marks keep a display that is off in the menu, and they are the only displays the safety net turns on again
/// (`DisplayPolicy.displaysToRestore`). macOS turns a display off for the login session only. A display that was
/// unplugged while it was off would keep its mark for good: it would stay "off" in the menu, and the safety net would try
/// to turn it on. `pruned` drops the mark of such a display once it is from an earlier session and the display is gone
/// for sure: not in the online list, and either macOS answers that it is not connected or the mark is from before a
/// restart. Any other mark stays, and the built-in display's mark always stays (see `pruned`).
public struct OffMarks: Equatable, Sendable {
    /// The name of each display that OpenDisplay turned off, by `CGDirectDisplayID`.
    public var names: [UInt32: String]
    /// The login session (`LoginSession`) each mark was made in. A mark saved by an earlier version, or made while
    /// the session was not known, has none.
    public var sessions: [UInt32: String]

    public init(names: [UInt32: String], sessions: [UInt32: String]) {
        self.names = names
        self.sessions = sessions
    }

    /// OpenDisplay turned the display `id` off, in the login session `session` (nil: not known).
    public mutating func markOff(_ id: UInt32, name: String, session: String?) {
        names[id] = name
        sessions[id] = session
    }

    /// The display `id` is on again.
    public mutating func markOn(_ id: UInt32) {
        names[id] = nil
        sessions[id] = nil
    }

    /// The marks at launch and at each refresh, in the login session `session` (nil: not known). `builtins`: the
    /// displays remembered as built-in. `online`: `CGGetOnlineDisplayList`. `reports`: what macOS answers now for the
    /// marked displays.
    ///
    /// - A mark from another session is dropped only if its display is not in `online`, and either the mark comes from
    ///   before a restart (a restart turns every display on again) or `CGDisplayIsOnline` answers 0 (not connected).
    ///   A display in `online` may still be connected and off, and so may one that macOS does not know now (-1, as
    ///   when it is off) or that has no report, within the same boot: it keeps its mark, the only way back to it for
    ///   the menu and the safety net.
    /// - The built-in display (remembered, or answered 1 by `CGDisplayIsBuiltin`) keeps its mark: the safety net needs
    ///   it, or a MacBook whose last external display is unplugged has no screen.
    /// - A mark without a session (saved by an earlier version) is kept and gets this session, so only a later session
    ///   can drop it.
    /// - Without a known session, no mark is dropped or stamped.
    public func pruned(session: String?, builtins: Set<UInt32>, online: [UInt32],
                       reports: [DisplayReport]) -> OffMarks {
        var marks = OffMarks(names: names, sessions: sessions.filter { names[$0.key] != nil })
        guard let session else { return marks }
        let reports = Dictionary(reports.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in names.keys {
            guard let made = marks.sessions[id] else {
                marks.sessions[id] = session
                continue
            }
            guard made != session, !builtins.contains(id), reports[id]?.isBuiltin != 1 else { continue }
            let restarted: Bool
            if let madeIn = LoginSession.boot(of: made), let now = LoginSession.boot(of: session) {
                restarted = madeIn != now
            } else {
                restarted = false
            }
            let unplugged = !online.contains(id) && reports[id]?.isOnline == 0
            if (restarted && !online.contains(id)) || unplugged {
                marks.markOn(id)
            }
        }
        return marks
    }
}

/// Identifies the login session, for `OffMarks`. It must not change during a login session, and must differ in the
/// next one, also after a logout without a restart. It starts with the boot session, so a restart can be told apart.
public enum LoginSession {
    /// The boot session (`kern.bootsessionuuid`), then the session of the window server
    /// (`CGSessionCopyCurrentDictionary`): its unique session ID (`CGSSessionUniqueSessionUUID`), or without one its
    /// audit session ID (`kCGSSessionAuditIDKey`), which can repeat after a restart. Without the boot session, the
    /// unique session ID alone. nil if the session is not known.
    public static func identifier(uniqueSession: String?, auditSession: Int?, bootSession: String?) -> String? {
        let uniqueSession = uniqueSession.flatMap { $0.isEmpty ? nil : $0 }
        guard let bootSession, !bootSession.isEmpty else { return uniqueSession }
        guard let login = uniqueSession ?? auditSession.map(String.init) else { return nil }
        return "\(bootSession)/\(login)"
    }

    /// The boot session in `identifier`, nil if it has none.
    static func boot(of identifier: String) -> String? {
        guard let slash = identifier.firstIndex(of: "/") else { return nil }
        return String(identifier[..<slash])
    }
}

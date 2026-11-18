/// The displays OpenDisplay turned off ("marks"), with their names, and the login session each mark was made in.
///
/// The marks keep a display that is off in the menu, and they are the only displays the safety net turns on again
/// (`DisplayPolicy.displaysToRestore`). macOS turns a display off for the login session only. So a mark from an earlier
/// session is stale: the display was unplugged while it was off, and with its mark it would stay "off" in the menu for
/// good, and the safety net would try to turn it on. `pruned` drops such marks, except the built-in display's.
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
    /// built-in displays, as far as they are known.
    ///
    /// - A mark from another session is dropped, unless its display is built-in: the safety net needs the built-in
    ///   display's mark, or a MacBook whose last external display is unplugged has no screen.
    /// - A mark without a session (saved by an earlier version) is kept and gets this session, so only a later session
    ///   can drop it.
    /// - Without a known session, no mark is dropped or stamped.
    public func pruned(session: String?, builtins: Set<UInt32>) -> OffMarks {
        var marks = OffMarks(names: names, sessions: sessions.filter { names[$0.key] != nil })
        guard let session else { return marks }
        for id in names.keys {
            guard let made = marks.sessions[id] else {
                marks.sessions[id] = session
                continue
            }
            if made != session && !builtins.contains(id) {
                marks.markOn(id)
            }
        }
        return marks
    }
}

/// Identifies the login session, for `OffMarks`. It must not change during a login session, and must differ in the
/// next one, also after a logout without a restart.
public enum LoginSession {
    /// From the session of the window server (`CGSessionCopyCurrentDictionary`): its unique session ID
    /// (`CGSSessionUniqueSessionUUID`). Without one, its audit session ID (`kCGSSessionAuditIDKey`) with the boot
    /// session (`kern.bootsessionuuid`), because audit session IDs can repeat after a restart. nil if neither is
    /// known.
    public static func identifier(uniqueSession: String?, auditSession: Int?, bootSession: String?) -> String? {
        if let uniqueSession, !uniqueSession.isEmpty { return uniqueSession }
        guard let auditSession, let bootSession, !bootSession.isEmpty else { return nil }
        return "\(bootSession)/\(auditSession)"
    }
}

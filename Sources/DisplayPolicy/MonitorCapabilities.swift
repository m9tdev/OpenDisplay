/// The VCP codes a monitor lists in its DDC capabilities string, with their allowed values, and where the app is in
/// reading them.
///
/// The app reads them once per monitor, over its DDC connection, and shows a row (contrast, input, color preset) only
/// for a code the monitor lists. A read is slow, so a refresh must not start a second one while the first is in flight,
/// and a failed read is tried again at the next refresh.
public enum MonitorCapabilities: Equatable, Sendable {
    /// Not read, or the last read failed or was dropped: the next refresh reads them.
    case unread
    /// A read is in flight.
    case reading
    /// The codes the monitor listed, each with its allowed values (empty for a range, like brightness). Empty when the
    /// capabilities string lists no codes.
    case read([UInt8: [UInt8]])

    /// True when a refresh should start a read.
    public var needsRead: Bool {
        switch self {
        case .unread: return true
        case .reading, .read: return false
        }
    }

    /// The codes the monitor listed, empty until they are read.
    public var codes: [UInt8: [UInt8]] {
        switch self {
        case .unread, .reading: return [:]
        case let .read(codes): return codes
        }
    }

    /// True unless a read listed codes without `code`. Without a list (not read yet, or none listed) the app cannot
    /// tell, so it asks the monitor.
    public func maySupport(_ code: UInt8) -> Bool {
        switch self {
        case .unread, .reading: return true
        case let .read(codes): return codes.isEmpty || codes[code] != nil
        }
    }

    /// A read was sent.
    public mutating func startRead() {
        self = .reading
    }

    /// The answer to the read: the parsed codes, or `nil` when the read failed (the next refresh tries again).
    public mutating func finishRead(_ codes: [UInt8: [UInt8]]?) {
        self = codes.map(MonitorCapabilities.read) ?? .unread
    }

    /// The display got another DDC connection to the same monitor. The answer to a read in flight is dropped, so the
    /// next refresh reads them again; so does a read that listed no codes, which tells nothing. Codes already listed
    /// stay: they belong to the monitor, not to the connection.
    public mutating func connectionChanged() {
        switch self {
        case .unread: break
        case .reading: self = .unread
        case let .read(codes): if codes.isEmpty { self = .unread }
        }
    }
}

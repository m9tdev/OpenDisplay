/// The state of one display, for the on/off decisions. Plain values, so the decisions can be tested without displays.
public struct DisplayState: Equatable, Sendable {
    /// `CGDirectDisplayID`.
    public var id: UInt32
    public var isBuiltin: Bool
    /// Connected (in `CGGetOnlineDisplayList`).
    public var isOnline: Bool
    /// On (in `CGGetActiveDisplayList`).
    public var isActive: Bool
    /// Not a real screen: for example the placeholder that macOS makes when no display is on.
    public var isVirtual: Bool
    /// OpenDisplay turned it off.
    public var isDisabledByUs: Bool

    public init(id: UInt32, isBuiltin: Bool = false, isOnline: Bool = true, isActive: Bool = true,
                isVirtual: Bool = false, isDisabledByUs: Bool = false) {
        self.id = id
        self.isBuiltin = isBuiltin
        self.isOnline = isOnline
        self.isActive = isActive
        self.isVirtual = isVirtual
        self.isDisabledByUs = isDisabledByUs
    }

    /// From what macOS reports about the display: `CGDisplayVendorNumber`, `CGDisplayModelNumber`, and the number of
    /// display modes. `DisplayPolicy.isVirtual` decides if it is virtual.
    public init(id: UInt32, isBuiltin: Bool, isOnline: Bool, isActive: Bool, vendor: UInt32, model: UInt32,
                modeCount: Int, isDisabledByUs: Bool) {
        self.init(id: id, isBuiltin: isBuiltin, isOnline: isOnline, isActive: isActive,
                  isVirtual: DisplayPolicy.isVirtual(vendor: vendor, model: model, isBuiltin: isBuiltin,
                                                     modeCount: modeCount),
                  isDisabledByUs: isDisabledByUs)
    }
}

/// What macOS answers about one display, as it answers: `CGDisplayIsBuiltin`, `CGDisplayIsOnline`, and
/// `CGDisplayIsActive` return a `boolean_t`, an Int32.
public struct DisplayReport: Equatable, Sendable {
    public var id: UInt32
    public var isBuiltin: Int32
    public var isOnline: Int32
    public var isActive: Int32
    public var vendor: UInt32
    public var model: UInt32
    public var modeCount: Int

    public init(id: UInt32, isBuiltin: Int32, isOnline: Int32, isActive: Int32, vendor: UInt32, model: UInt32,
                modeCount: Int) {
        self.id = id
        self.isBuiltin = isBuiltin
        self.isOnline = isOnline
        self.isActive = isActive
        self.vendor = vendor
        self.model = model
        self.modeCount = modeCount
    }
}

/// When a display may turn off, and which display to turn on again.
public enum DisplayPolicy {
    /// The states of the displays, from what macOS reports: `CGGetOnlineDisplayList`, `CGGetActiveDisplayList`, a
    /// report for each display in them and for each display we turned off (`disabled`), which may be in neither.
    ///
    /// For a display ID that macOS does not know now, such as the built-in display while it is off, the
    /// `CGDisplayIs…` functions return -1, not 0. So "online" and "active" come from the lists, and only an answer of 1
    /// means built-in.
    public static func states(online: [UInt32], active: [UInt32], reports: [DisplayReport],
                              disabled: Set<UInt32>) -> [DisplayState] {
        let online = Set(online), active = Set(active)
        return reports.map { report in
            DisplayState(id: report.id, isBuiltin: isTrue(report.isBuiltin), isOnline: online.contains(report.id),
                         isActive: active.contains(report.id), vendor: report.vendor, model: report.model,
                         modeCount: report.modeCount, isDisabledByUs: disabled.contains(report.id))
        }
    }

    /// True only for an answer of 1 from a `CGDisplayIs…` function: it returns -1 for a display it does not know.
    public static func isTrue(_ answer: Int32) -> Bool { answer == 1 }

    /// True for a display that is not a real screen, from its `CGDisplayVendorNumber`, `CGDisplayModelNumber`, and
    /// number of display modes.
    ///
    /// When the last display that is on goes away (for example, the TV is unplugged while the built-in display is
    /// off), macOS does not turn another display on: WindowServer makes a virtual placeholder display, with vendor
    /// "unkn" and model "virt", and makes it the main display. The Mac then has no screen.
    public static func isVirtual(vendor: UInt32, model: UInt32, isBuiltin: Bool, modeCount: Int) -> Bool {
        !isBuiltin && vendor == placeholderVendor && model == placeholderModel
    }

    /// "unkn" and "virt", in ASCII.
    static let placeholderVendor: UInt32 = 0x756E_6B6E
    static let placeholderModel: UInt32 = 0x7669_7274

    /// True if turning off the displays `ids` leaves a physical display on. Virtual displays do not count, because
    /// you cannot see them. Only without any physical display (a Mac mini with virtual displays only) a virtual
    /// display is enough.
    public static func canDisable(_ ids: Set<UInt32>, in displays: [DisplayState]) -> Bool {
        let remaining = displays.filter { $0.isActive && !ids.contains($0.id) }
        guard displays.contains(where: { !$0.isVirtual }) else { return !remaining.isEmpty }
        return remaining.contains { !$0.isVirtual }
    }

    /// The displays to try to turn on again, in order, because no display is on. Empty if nothing needs to change.
    /// Only displays that OpenDisplay turned off, and no virtual ones. The built-in display first, then the online
    /// displays, then the others (macOS may report a display that is off as offline, and the built-in display
    /// as not built-in then).
    public static func displaysToRestore(in displays: [DisplayState]) -> [UInt32] {
        guard !displays.contains(where: { $0.isActive && !$0.isVirtual }) else { return [] }
        func rank(_ display: DisplayState) -> Int { display.isBuiltin ? 0 : display.isOnline ? 1 : 2 }
        return displays
            .filter { !$0.isActive && !$0.isVirtual && $0.isDisabledByUs }
            .sorted { (rank($0), $0.id) < (rank($1), $1.id) }
            .map(\.id)
    }
}

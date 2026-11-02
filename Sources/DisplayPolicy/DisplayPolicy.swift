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

    /// From what macOS reports about the display: `CGDisplayVendorNumber` and `CGDisplayModelNumber`.
    /// `DisplayPolicy.isVirtual` decides if it is virtual.
    public init(id: UInt32, isBuiltin: Bool, isOnline: Bool, isActive: Bool, vendor: UInt32, model: UInt32,
                isDisabledByUs: Bool) {
        self.init(id: id, isBuiltin: isBuiltin, isOnline: isOnline, isActive: isActive,
                  isVirtual: DisplayPolicy.isVirtual(vendor: vendor, model: model, isBuiltin: isBuiltin),
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

    public init(id: UInt32, isBuiltin: Int32, isOnline: Int32, isActive: Int32, vendor: UInt32, model: UInt32) {
        self.id = id
        self.isBuiltin = isBuiltin
        self.isOnline = isOnline
        self.isActive = isActive
        self.vendor = vendor
        self.model = model
    }
}

/// When a display may turn off, and which display to turn on again.
public enum DisplayPolicy {
    /// The states of the displays, from what macOS reports: `CGGetOnlineDisplayList`, `CGGetActiveDisplayList`, a
    /// report for each display in them and for each display we turned off (`disabled`), which may be in neither.
    /// `builtins`: the displays that were built-in when they were last on.
    ///
    /// For a display ID that macOS does not know now, such as the built-in display while it is off, the
    /// `CGDisplayIs…` functions return -1, not 0. So "online" and "active" come from the lists. Built-in is an answer
    /// of 1, or, while macOS does not know the display (-1), the display is in `builtins`.
    public static func states(online: [UInt32], active: [UInt32], reports: [DisplayReport],
                              disabled: Set<UInt32>, builtins: Set<UInt32> = []) -> [DisplayState] {
        let online = Set(online), active = Set(active)
        return reports.map { report in
            DisplayState(id: report.id,
                         isBuiltin: isBuiltin(answer: report.isBuiltin, id: report.id, builtins: builtins),
                         isOnline: online.contains(report.id), isActive: active.contains(report.id),
                         vendor: report.vendor, model: report.model, isDisabledByUs: disabled.contains(report.id))
        }
    }

    /// True only for an answer of 1 from a `CGDisplayIs…` function: it returns -1 for a display it does not know.
    public static func isTrue(_ answer: Int32) -> Bool { answer == 1 }

    /// Built-in, from the answer of `CGDisplayIsBuiltin`: 1 is built-in, 0 is not, and for any other answer (-1, while
    /// macOS does not know the display), the remembered built-in displays decide.
    public static func isBuiltin(answer: Int32, id: UInt32, builtins: Set<UInt32>) -> Bool {
        switch answer {
        case 1: true
        case 0: false
        default: builtins.contains(id)
        }
    }

    /// The remembered built-in displays after macOS answered `CGDisplayIsBuiltin` for the displays that are on: an
    /// answer of 1 adds the display, 0 removes it (its ID now belongs to another display), and any other answer keeps
    /// what was remembered.
    public static func rememberedBuiltins(_ builtins: Set<UInt32>, answers: [UInt32: Int32]) -> Set<UInt32> {
        var builtins = builtins
        for (id, answer) in answers {
            switch answer {
            case 1: builtins.insert(id)
            case 0: builtins.remove(id)
            default: break
            }
        }
        return builtins
    }

    /// True for a display that is not a real screen, from its `CGDisplayVendorNumber` and `CGDisplayModelNumber`.
    ///
    /// When the last display that is on goes away (for example, the TV is unplugged while the built-in display is
    /// off), macOS does not turn another display on: WindowServer makes a virtual placeholder display, with vendor
    /// "unkn" and model "virt", and makes it the main display. The Mac then has no screen.
    public static func isVirtual(vendor: UInt32, model: UInt32, isBuiltin: Bool) -> Bool {
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

    /// True if a failure to turn the display `id` on again should show an error: for the built-in display, and for a
    /// display that is online. An offline display that is not remembered as built-in may have been unplugged after
    /// OpenDisplay turned it off (a stale ID), so its failure shows no error. But macOS also reports a display that is
    /// off as offline, so it is still tried again (see `restoreOutcome`).
    public static func showsRestoreError(of id: UInt32, in displays: [DisplayState]) -> Bool {
        guard let display = displays.first(where: { $0.id == id }) else { return false }
        return display.isBuiltin || display.isOnline
    }

    /// What to do after an attempt to turn a display on again: try again, the error to show (nil: none), and whether
    /// to clear an error that an earlier attempt showed.
    public struct RestoreOutcome: Equatable, Sendable {
        public var retries: Bool
        public var error: String?
        public var clearsError: Bool

        public init(retries: Bool, error: String?, clearsError: Bool = false) {
            self.retries = retries
            self.error = error
            self.clearsError = clearsError
        }
    }

    /// After an attempt to turn a display on again: `restored` is the display that turned on, if any, and `failures`
    /// the displays that did not, with their errors. `attempt` counts from 0, and at most `maxRetries` retries follow.
    /// While no display came back on, it tries again, also after failures that show no error: the display may only be
    /// off, not unplugged.
    public static func restoreOutcome(restored: UInt32?, failures: [(id: UInt32, error: String)],
                                      in displays: [DisplayState], attempt: Int, maxRetries: Int) -> RestoreOutcome {
        guard restored == nil else { return RestoreOutcome(retries: false, error: nil, clearsError: true) }
        let error = failures.first { showsRestoreError(of: $0.id, in: displays) }?.error
        return RestoreOutcome(retries: !failures.isEmpty && attempt < maxRetries, error: error)
    }

    /// The error to show after a check found a physical display on, or turned one on again. `restoreError` is the
    /// error that an earlier failed attempt to turn a display on showed.
    public static func errorAfterRestore(lastError: String?, restoreError: String?) -> String? {
        lastError
    }

    /// The displays to try to turn on again, in order, because no display is on. Empty if nothing needs to change.
    /// Only displays that OpenDisplay turned off, and no virtual ones. The built-in display first, then the online
    /// displays, then the others, each by ID (macOS may report a display that is off as offline).
    public static func displaysToRestore(in displays: [DisplayState]) -> [UInt32] {
        guard !displays.contains(where: { $0.isActive && !$0.isVirtual }) else { return [] }
        func rank(_ display: DisplayState) -> Int { display.isBuiltin ? 0 : display.isOnline ? 1 : 2 }
        return displays
            .filter { !$0.isActive && !$0.isVirtual && $0.isDisabledByUs }
            .sorted { (rank($0), $0.id) < (rank($1), $1.id) }
            .map(\.id)
    }
}

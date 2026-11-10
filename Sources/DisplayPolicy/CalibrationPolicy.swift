import Foundation

/// The brightness calibration compares two displays by eye, so while it runs, it alone sets their brightness.
/// Whatever it changed (the brightness of both displays, automatic brightness, True Tone) comes back when it ends:
/// with Cancel or Save, when the app quits, or at the next launch after a crash.
public enum CalibrationPolicy {
    /// What the app does with a brightness key.
    public enum BrightnessKey: Equatable, Sendable {
        /// The usual: the app or macOS changes a brightness.
        case normal
        /// Drop the key, so neither the app nor macOS changes a brightness.
        case ignore
    }

    public static func brightnessKey(isCalibrating: Bool) -> BrightnessKey {
        isCalibrating ? .ignore : .normal
    }

    /// True if a brightness change from outside the calibration (a key, a slider, a preset) may reach the displays.
    public static func allowsBrightnessChange(isCalibrating: Bool) -> Bool {
        !isCalibrating
    }

    /// The smallest change of the built-in brightness that the calibration takes as a change by someone else.
    /// One brightness key step is 1/64 or more.
    public static let builtinTolerance: Float = 0.01

    /// True if the built-in brightness moved away from the level the calibration set, so the calibration must set it
    /// again. macOS changes it with the brightness keys when the app does not catch them (no Accessibility
    /// permission, or the keys are off in Settings).
    /// - Parameters:
    ///   - notified: The built-in brightness that macOS reports.
    ///   - calibrationLevel: The level the calibration set last, or nil if it set none yet.
    public static func mustSetBuiltinAgain(notified: Float, calibrationLevel: Float?) -> Bool {
        guard let calibrationLevel else { return false }
        return abs(notified - calibrationLevel) >= builtinTolerance
    }

    /// What the synced displays do after a calibration was saved or reset, which changes their curves: the same
    /// shared brightness now gives another level.
    public enum SyncedAfterChange: Equatable, Sendable {
        /// Follow the built-in display again, as after any change of it.
        case followBuiltin
        /// Set the shared brightness again with the new curves.
        case applyShared(Double)
        /// Nothing to set.
        case nothing
    }

    /// - Parameters:
    ///   - builtinOn: The built-in display is on in the app.
    ///   - sharedBrightness: The shared slider position of the synced displays, or nil if they have none yet.
    public static func syncedAfterChange(builtinOn: Bool, sharedBrightness: Double?) -> SyncedAfterChange {
        if builtinOn { return .followBuiltin }
        // Without the built-in display there is nothing to follow, but the shared brightness works without it.
        return sharedBrightness.map { .applyShared($0) } ?? .nothing
    }
}

/// Keeps the built-in display at the calibration's level when macOS changes it, without a fast loop: if macOS rounds
/// or clamps the level it reports, and reports each set, each set again would bring another report. If macOS reported
/// each set more than a second late and never with the level, it would go on at about one set a second until the
/// calibration sets another level or ends.
public struct CalibrationBuiltinWatch: Equatable, Sendable {
    /// The level the calibration set last, or nil if it set none yet.
    public private(set) var level: Float?
    /// The reported value of the last set again, and when that set was. A report of the same value soon after the
    /// set is its answer: macOS rounds or clamps the level.
    private var answered: Answer?
    private struct Answer: Equatable, Sendable {
        var value: Float
        var time: Double
    }
    /// When the last set again was.
    private var lastSet: Double?
    /// Sets again from reports. Back to 0 when the calibration sets a level, when a report away from the level comes
    /// more than `quietTime` after both the last report away from it and the last set again, and when a settle check
    /// finds the level.
    private var setsAgain = 0
    /// When macOS last reported a value away from `level`.
    private var lastAway: Double?
    /// True from a report away from the level until the settle check.
    private var settleCheckDue = false
    /// Sets again from settle checks. Back to 0 when the calibration sets a level, when a report away from the level
    /// comes more than `answerTime` after the last set again, and when a settle check finds the level.
    private var settlesAgain = 0
    /// The value the last settle check set again for, reset with `settlesAgain`.
    private var settledValue: Float?

    /// The most sets again in a row from reports, and also from settle checks.
    public static let maximumSetsAgain = 8
    /// Seconds without reports away from the level, after which the reports have stopped: a new one is a new change
    /// (another key press), and the settle check reads the brightness.
    public static let quietTime = 1.0
    /// Seconds after a set again in which a report of the value it answered is the answer to that set.
    public static let answerTime = 0.2

    public init() {}

    /// The calibration set the built-in display to `level`.
    public mutating func calibrationSet(_ level: Float) {
        self = Self()
        self.level = level
    }

    /// macOS reports the built-in brightness `value`. Returns the level to set again, or nil.
    /// - Parameter time: Now, in seconds (any clock that only goes forward).
    public mutating func reported(_ value: Float, at time: Double) -> Float? {
        guard let level, CalibrationPolicy.mustSetBuiltinAgain(notified: value, calibrationLevel: level) else {
            answered = nil
            return nil
        }
        // A new change, not an answer to a set again: start over. A report of the level does not start over, because
        // in a loop such reports can come between the others.
        if Self.isQuiet(since: lastAway, at: time), Self.isQuiet(since: lastSet, at: time) {
            answered = nil
            setsAgain = 0
        }
        // Not an answer to a set again (those come soon after it): a new change, such as another held key, that the
        // settle check must put back even if it ends on the value of the last one.
        if lastSet.map({ time - $0 > Self.answerTime }) ?? true {
            settlesAgain = 0
            settledValue = nil
        }
        lastAway = time
        settleCheckDue = true
        if let answered, time - answered.time <= Self.answerTime,
           abs(value - answered.value) < CalibrationPolicy.builtinTolerance { return nil }
        guard setsAgain < Self.maximumSetsAgain else { return nil }
        setsAgain += 1
        return setAgain(answering: value, at: time)
    }

    /// When to read the built-in brightness once and pass it to `settled(_:at:)`, or nil if no check is due. Fast
    /// key presses can use up the sets again from reports, so after they stop, this check puts the level back.
    public var settleCheckTime: Double? {
        guard settleCheckDue, let lastAway else { return nil }
        return lastAway + Self.quietTime
    }

    /// The built-in brightness `value`, read once after `settleCheckTime`. Returns the level to set again, or nil.
    public mutating func settled(_ value: Float, at time: Double) -> Float? {
        // Too early, so a report could still come: no check, and the check stays due. The app checks a little after
        // `settleCheckTime`, and each report schedules the check again, so it does not need to be scheduled here.
        guard let level, let lastAway, time - lastAway > Self.quietTime else { return nil }
        settleCheckDue = false
        guard CalibrationPolicy.mustSetBuiltinAgain(notified: value, calibrationLevel: level) else {
            // On the level: nothing is set, so nothing can go on.
            answered = nil
            setsAgain = 0
            settlesAgain = 0
            settledValue = nil
            return nil
        }
        // The same value as at the last check: macOS rounds or clamps the level, so setting it again changes nothing.
        if let settledValue, abs(value - settledValue) < CalibrationPolicy.builtinTolerance { return nil }
        guard settlesAgain < Self.maximumSetsAgain else { return nil }
        settlesAgain += 1
        settledValue = value
        return setAgain(answering: value, at: time)
    }

    private mutating func setAgain(answering value: Float, at time: Double) -> Float? {
        answered = Answer(value: value, time: time)
        lastSet = time
        return level
    }

    private static func isQuiet(since time: Double?, at now: Double) -> Bool {
        time.map { now - $0 > quietTime } ?? true
    }
}

/// What the calibration changed, saved while it runs. If the app ends without a chance to put it back (a crash),
/// the next launch puts it back from this record.
public struct CalibrationRecord: Codable, Equatable, Sendable {
    /// The calibration turned automatic brightness off.
    public var autoBrightness: Bool
    /// The calibration turned True Tone off.
    public var trueTone: Bool
    /// The built-in display's slider position before the calibration, or nil if it was not known.
    public var builtinBrightness: Double?
    /// The external display's stable key: its display ID can change at the next launch.
    public var externalKey: String
    /// The external display's slider position before the calibration, or nil if it was not known yet (its first
    /// DDC read had not ended).
    public var externalBrightness: Double?

    public init(autoBrightness: Bool, trueTone: Bool, builtinBrightness: Double?, externalKey: String,
                externalBrightness: Double?) {
        self.autoBrightness = autoBrightness
        self.trueTone = trueTone
        self.builtinBrightness = builtinBrightness
        self.externalKey = externalKey
        self.externalBrightness = externalBrightness
    }

    /// For UserDefaults.
    public var data: Data? {
        try? JSONEncoder().encode(self)
    }

    /// From UserDefaults. nil if there is no record, or it cannot be read.
    public init?(data: Data?) {
        guard let data, let record = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = record
    }

    /// The record of a new calibration, while `unfinished` (from a calibration the app could not finish) is not put
    /// back yet: what that one turned off and the brightness from before it must still come back.
    public func keeping(_ unfinished: CalibrationRecord?) -> CalibrationRecord {
        guard let unfinished else { return self }
        // The new calibration finds what the unfinished one changed, so its values are the unfinished one's.
        let sameExternal = unfinished.externalKey == externalKey
        return CalibrationRecord(
            autoBrightness: autoBrightness || unfinished.autoBrightness,
            trueTone: trueTone || unfinished.trueTone,
            builtinBrightness: unfinished.builtinBrightness ?? builtinBrightness,
            externalKey: externalKey,
            externalBrightness: sameExternal ? unfinished.externalBrightness ?? externalBrightness : externalBrightness)
    }

    /// The external display, when the calibration ends.
    public enum External: Equatable, Sendable {
        /// Not connected, or off.
        case absent
        /// It follows the built-in display, so it gets its brightness from it.
        case synced
        /// - Parameter brightness: Its slider position in the app now, if known. Used only when the record has
        ///   none: the calibration sets the monitor directly, so the app's value is still the one from before.
        ///   At a launch, pass nil: the value read from the monitor is the calibration's.
        case own(brightness: Double?)
    }

    /// What to put back. The built-in display first: it also sets a synced external display.
    public struct Restore: Equatable, Sendable {
        public var autoBrightness: Bool
        public var trueTone: Bool
        public var builtinBrightness: Double?
        public var externalBrightness: Double?

        public init(autoBrightness: Bool, trueTone: Bool, builtinBrightness: Double?, externalBrightness: Double?) {
            self.autoBrightness = autoBrightness
            self.trueTone = trueTone
            self.builtinBrightness = builtinBrightness
            self.externalBrightness = externalBrightness
        }
    }

    public func restore(external: External) -> Restore {
        let externalBrightness: Double? = switch external {
        case .absent, .synced: nil
        case .own(let brightness): self.externalBrightness ?? brightness
        }
        return Restore(autoBrightness: autoBrightness, trueTone: trueTone, builtinBrightness: builtinBrightness,
                       externalBrightness: externalBrightness)
    }

    /// Puts back an unfinished calibration (after a crash), at a launch or when a display comes back. A part for a
    /// display that is not there waits for it: for example the built-in display with the lid closed, or an external
    /// display that is unplugged. True Tone is not tied to a display, so it always comes back now.
    /// - Parameters:
    ///   - builtin: The built-in display is there and on.
    ///   - external: The external display of the record. With its own brightness, pass `.own(brightness: nil)`: the
    ///     value the app read from the monitor is the calibration's.
    /// - Returns: What to put back now, and the record of what waits, or nil when nothing waits.
    public func restoreUnfinished(builtin: Bool, external: External) -> (now: Restore, pending: CalibrationRecord?) {
        var now = restore(external: external)
        var pending = self
        pending.trueTone = false
        if builtin {
            pending.autoBrightness = false
            pending.builtinBrightness = nil
        } else {
            now.autoBrightness = false
            now.builtinBrightness = nil
        }
        // A synced external display gets its brightness from the built-in one.
        let externalDone = switch external {
        case .absent: false
        case .synced: builtin
        case .own: true
        }
        if externalDone {
            pending.externalBrightness = nil
        }
        let waits = pending.autoBrightness || pending.builtinBrightness != nil || pending.externalBrightness != nil
        return (now, waits ? pending : nil)
    }

    /// Puts back what the calibration changed when it ends: with Cancel or Save, when a display goes away, or when
    /// the app quits. The built-in display can be off by now (the app turned it off, which ended the calibration).
    /// Then its part waits for it as after a crash (see `restoreUnfinished`). A synced external display gets its own
    /// value back now, as one not synced does: it would otherwise keep the calibration's level until the built-in
    /// display comes back, which may never happen. With the lid closed, the built-in display is still on in the app
    /// until the next refresh, so everything comes back now.
    /// - Parameters:
    ///   - builtin: The built-in display is on in the app.
    ///   - synced: The external display follows the built-in display.
    ///   - externalBrightness: The external display's slider position in the app now, if known. Used only when the
    ///     record has none: the calibration sets the monitor directly, so the app's value is still the one from before.
    /// - Returns: What to put back now, and the record of what waits, or nil when nothing waits.
    public func restoreAtEnd(builtin: Bool, synced: Bool, externalBrightness: Double?)
        -> (now: Restore, pending: CalibrationRecord?) {
        restoreUnfinished(builtin: builtin,
                          external: synced && builtin ? .synced : .own(brightness: externalBrightness))
    }
}

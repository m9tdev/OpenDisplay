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
}

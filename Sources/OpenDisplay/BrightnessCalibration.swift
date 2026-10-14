import CoreGraphics
import Foundation

/// The measured brightness of an external display model, from matching it by eye with the built-in display.
///
/// It describes the display model, not this Mac, so the same values work for each display of that model with the
/// same monitor settings. The format is versioned JSON, so calibrations can be shared later.
struct BrightnessCalibration: Codable, Equatable {
    var version = 1
    var vendor: UInt32
    var model: UInt32
    var name: String
    /// The light at the lowest DDC level, as a part of the display's maximum light.
    /// Nil for a display without DDC: then only `maximum` is known.
    var lowest: Double?
    /// The shape of the curve between the lowest and the highest DDC level (see `ExternalCurve`). Nil without DDC.
    var gamma: Double?
    /// The maximum light of the display, as a part of the maximum light of the reference display.
    /// Without DDC: the light at the backlight level that was set with the display's own buttons.
    var maximum: Double
    /// The monitor settings during the calibration, by name (see `monitorSettings`). Other settings give other light.
    var settings: [String: UInt16]?
    /// The Mac model with the reference (built-in) display, for example "Mac14,9".
    var reference: String
    var date: Date

    /// The key of a display model: vendor and model number, without the serial number.
    static func key(vendor: UInt32, model: UInt32) -> String {
        "\(vendor)-\(model)"
    }

    var key: String { Self.key(vendor: vendor, model: model) }

    var usesDDC: Bool { lowest != nil && gamma != nil }

    /// - Parameter synced: True if the display follows the built-in display. Then it gives the same light as the
    ///   built-in display, and not the same part of its own maximum.
    func curve(synced: Bool) -> ExternalCurve {
        let estimate = ExternalCurve()
        return ExternalCurve(lowest: lowest ?? estimate.lowest, gamma: gamma ?? estimate.gamma, scale: synced ? 1 / maximum : 1)
    }

    /// The monitor settings (DDC) that change the light of the display.
    static let monitorSettings: [(name: String, title: String, vcp: UInt8)] = [
        ("contrast", "Contrast", VCP.contrast),
        ("colorPreset", "Color preset", VCP.colorPreset),
        ("gamma", "Gamma", 0x72),
        ("pictureMode", "Picture mode", 0xDC),
    ]

    /// The titles of the monitor settings that are now different from the settings during the calibration.
    func changedSettings(_ current: [String: UInt16]?) -> [String] {
        guard let settings, let current else { return [] }
        return Self.monitorSettings.filter { setting in
            guard let old = settings[setting.name], let new = current[setting.name] else { return false }
            return old != new
        }.map(\.title)
    }

    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}

/// The calibrations of all display models, saved in the user defaults.
enum CalibrationStore {
    private static let key = "brightnessCalibrations"

    static func load() -> [String: BrightnessCalibration] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: BrightnessCalibration].self, from: data)) ?? [:]
    }

    static func save(_ calibrations: [String: BrightnessCalibration]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(calibrations), forKey: key)
    }
}

/// The four matches the user makes by eye. Light values are parts of the built-in display's maximum light.
struct CalibrationMatches {
    /// The built-in light that looks the same as the external display at its lowest DDC level.
    var lowest: Double
    var top: Top
    /// The DDC level (0...1) that looks the same as `middleLight`.
    var middleLevel: Double
    /// The built-in light that looks the same as the external display at DDC level `middleReferenceLevel`.
    var middleReferenceLight: Double

    /// The built-in display's light in the step that the user matches with the external display.
    static let middleLight = BrightnessCurve.light(slider: 0.5)
    /// The external display's DDC level in the step that the user matches with the built-in display.
    static let middleReferenceLevel = 0.5

    enum Top {
        /// Both displays look the same at their maximum.
        case same
        /// The built-in light that looks the same as the external display at its maximum.
        case builtinBrighter(light: Double)
        /// The DDC level that looks the same as the built-in display at its maximum.
        case externalBrighter(level: Double)
    }

    /// The curve that fits the matches best, and how well it fits: the average error as a factor of light
    /// (1.1: the measured light is about 10 % off the curve).
    ///
    /// The lowest match is exact. The other three matches give the maximum and the shape, with one match more
    /// than needed, so errors of the eye partly cancel.
    func fit() -> (lowest: Double, gamma: Double, maximum: Double, error: Double) {
        let lowestLight = max(lowest, 1e-4)
        var best = (lowest: 0.1, gamma: 1.0, maximum: 1.0, error: Double.infinity)
        // A search over a grid is fast enough (about 40,000 curves) and always finds the best curve.
        for i in 0..<200 {
            let gamma = 0.25 * pow(16, Double(i) / 199)  // 0.25...4
            for j in 0..<200 {
                let lowest = 0.002 * pow(400, Double(j) / 199)  // 0.002...0.8
                let maximum = lowestLight / lowest
                let curve = ExternalCurve(lowest: lowest, gamma: gamma)
                var errors = [
                    log(maximum * curve.light(level: middleLevel) / Self.middleLight),
                    log(maximum * curve.light(level: Self.middleReferenceLevel) / max(middleReferenceLight, 1e-4)),
                ]
                switch top {
                case .same: errors.append(log(maximum))
                case .builtinBrighter(let light): errors.append(log(maximum / max(light, 1e-4)))
                case .externalBrighter(let level): errors.append(log(maximum * curve.light(level: level)))
                }
                let error = (errors.map { $0 * $0 }.reduce(0, +) / Double(errors.count)).squareRoot()
                if error < best.error {
                    best = (lowest, gamma, maximum, error)
                }
            }
        }
        return (best.lowest, best.gamma, best.maximum, exp(best.error))
    }
}

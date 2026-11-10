import CoreGraphics
import DisplayPolicy
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

    /// The curve without sync. With sync, `DisplayManager` sets its scale.
    var curve: ExternalCurve {
        let estimate = ExternalCurve()
        return ExternalCurve(lowest: lowest ?? estimate.lowest, gamma: gamma ?? estimate.gamma)
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
        StoredJSON.save(calibrations, forKey: key)
    }
}

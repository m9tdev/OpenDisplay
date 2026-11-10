import Foundation

/// The step at the highest brightness of the calibration: the user selects the brighter display and moves its
/// slider until it looks the same as the other display.
public enum CalibrationTop {
    /// The display that is brighter when both are at their highest level.
    public enum Brighter: Equatable, Sendable {
        case builtin, external, same
    }

    /// The range of the slider of the brighter display. Not 0: there the light is 0, which matches no display (the
    /// built-in display turns black), and the maximum of an external display that is brighter would be infinite.
    public static func sliderRange(_ brighter: Brighter) -> ClosedRange<Double> {
        0.01...1
    }

    /// For an external display without DDC: its maximum light, as a part of the built-in display's maximum light.
    /// Always finite and above 0.
    /// - Parameters:
    ///   - brighter: The brighter display, or nil if the user selected none.
    ///   - slider: The position of the brighter display's slider. Outside `sliderRange`, the nearest end.
    public static func maximumWithoutDDC(brighter: Brighter?, slider: Double) -> Double {
        guard let brighter else { return 1 }
        let range = sliderRange(brighter)
        let light = BrightnessCurve.light(slider: min(max(slider, range.lowerBound), range.upperBound))
        switch brighter {
        case .builtin: return light
        case .external: return 1 / light
        case .same: return 1
        }
    }
}

extension CalibrationPolicy {
    /// True if a calibration's maximum light can be shown and saved: finite and above 0. JSON cannot hold an infinite
    /// number, and the app divides by the maximum.
    public static func isUsable(maximum: Double) -> Bool {
        maximum.isFinite && maximum > 0
    }
}

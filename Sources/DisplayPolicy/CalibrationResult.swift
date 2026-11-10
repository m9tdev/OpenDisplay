import Foundation

/// The step at the highest brightness of the calibration: the user selects the brighter display and moves its
/// slider until it looks the same as the other display.
public enum CalibrationTop {
    /// The display that is brighter when both are at their highest level.
    public enum Brighter: Equatable, Sendable {
        case builtin, external, same
    }

    /// The range of the slider of the brighter display.
    public static func sliderRange(_ brighter: Brighter) -> ClosedRange<Double> {
        switch brighter {
        case .builtin, .same: 0.01...1
        case .external: 0...1
        }
    }

    /// For an external display without DDC: its maximum light, as a part of the built-in display's maximum light.
    /// - Parameters:
    ///   - brighter: The brighter display, or nil if the user selected none.
    ///   - slider: The position of the brighter display's slider.
    public static func maximumWithoutDDC(brighter: Brighter?, slider: Double) -> Double {
        switch brighter {
        case .builtin: BrightnessCurve.light(slider: slider)
        case .external: 1 / BrightnessCurve.light(slider: slider)
        case .same, nil: 1
        }
    }
}

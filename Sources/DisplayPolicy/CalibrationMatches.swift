import Foundation

/// The four matches the user makes by eye. Light values are parts of the built-in display's maximum light.
public struct CalibrationMatches: Equatable, Sendable {
    /// The built-in light that looks the same as the external display at its lowest DDC level.
    public var lowest: Double
    public var top: Top
    /// The DDC level (0...1) that looks the same as `middleLight`.
    public var middleLevel: Double
    /// The built-in light that looks the same as the external display at DDC level `middleReferenceLevel`.
    public var middleReferenceLight: Double

    /// The built-in display's light in the step that the user matches with the external display.
    public static let middleLight = BrightnessCurve.light(slider: 0.5)
    /// The external display's DDC level in the step that the user matches with the built-in display.
    public static let middleReferenceLevel = 0.5

    public enum Top: Equatable, Sendable {
        /// Both displays look the same at their maximum.
        case same
        /// The built-in light that looks the same as the external display at its maximum.
        case builtinBrighter(light: Double)
        /// The DDC level that looks the same as the built-in display at its maximum.
        case externalBrighter(level: Double)
    }

    public init(lowest: Double, top: Top, middleLevel: Double, middleReferenceLight: Double) {
        self.lowest = lowest
        self.top = top
        self.middleLevel = middleLevel
        self.middleReferenceLight = middleReferenceLight
    }

    /// The curve that fits the matches best, and how well it fits: the average error as a factor of light
    /// (1.1: the measured light is about 10 % off the curve).
    ///
    /// The lowest match is exact. The other three matches give the maximum and the shape, with one match more
    /// than needed, so errors of the eye partly cancel.
    public func fit() -> (lowest: Double, gamma: Double, maximum: Double, error: Double) {
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

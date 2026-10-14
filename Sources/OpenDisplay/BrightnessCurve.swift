import Foundation

/// The brightness curve of macOS, so all brightness sliders follow it and synced displays match.
///
/// Eyes see brightness on a curve: each step that multiplies the light by the same factor looks about the same.
/// macOS maps its slider like this. Measured on the built-in display with `DisplayServicesGetLinearBrightness`
/// (light output, 1 = maximum):
///
///     slider  0.0     0.1     0.2     0.3     0.4     0.5     0.6     0.7     0.8     0.9     1.0
///     light   0.0024  0.0058  0.0152  0.0402  0.1060  0.2800  0.3612  0.4659  0.6010  0.7752  1.0000
///
/// Each half is exponential: per 0.1 step, the light is 2.64× higher in the lower half and 1.29× higher in the upper half.
/// At exactly 0, macOS turns the backlight off, so the light is 0 (black).
enum BrightnessCurve {
    private static let middle = 0.28
    private static let lowerStep = 2.64
    private static let upperStep = 1.29

    /// The light output (0...1) for a slider position (0...1).
    static func light(slider: Double) -> Double {
        guard slider > 0 else { return 0 }
        let steps = (min(max(slider, 0), 1) - 0.5) * 10
        return min(middle * pow(steps < 0 ? lowerStep : upperStep, steps), 1)
    }

    /// The slider position for a light output. The inverse of `light(slider:)`.
    static func slider(light: Double) -> Double {
        let light = max(light, 1e-6)
        let steps = log(light / middle) / log(light < middle ? lowerStep : upperStep)
        return min(max(0.5 + steps / 10, 0), 1)
    }
}

/// How a display makes the light that the brightness slider asks for.
enum BrightnessControl {
    /// The built-in display: macOS's own brightness value, which already follows the curve. The slider is that value.
    case builtin
    /// An external display over DDC, with software dimming below its lowest level.
    case external(ExternalCurve)
    /// No brightness control: software dimming only.
    case software

    /// The hardware level (nil: leave it as it is) and the software dimming factor for a slider position.
    func split(_ slider: Double) -> (level: Double?, dimming: Double) {
        let slider = min(max(slider, 0), 1)
        switch self {
        case .builtin:
            // Level 0 turns the built-in display black (macOS fades the image out), so the slider stays just above it.
            // The brightness keys can still go to 0; then synced external displays also go black.
            return (max(slider, 0.01), 1)
        case .external(let curve):
            let light = min(BrightnessCurve.light(slider: slider) * curve.scale, 1)
            return light >= curve.lowest ? (curve.level(light: light), 1) : (0, light / curve.lowest)
        case .software:
            return (nil, BrightnessCurve.light(slider: slider))
        }
    }

    /// The slider position for a hardware level and a software dimming factor. The inverse of `split`.
    func slider(level: Double?, dimming: Double) -> Double {
        switch self {
        case .builtin:
            return min(max(level ?? 1, 0), 1)
        case .external(let curve):
            let light = dimming < 1 ? dimming * curve.lowest : curve.light(level: level ?? 1)
            return BrightnessCurve.slider(light: light / curve.scale)
        case .software:
            return BrightnessCurve.slider(light: dimming)
        }
    }
}

/// How the light of an external display follows its DDC level, as a part of its maximum light:
/// light = lowest + (1 - lowest) * level^gamma. Without a calibration, the values are estimates (see `BrightnessCalibration`).
struct ExternalCurve: Equatable {
    /// The light at the lowest DDC level. An estimate: typical external displays have 30–50 nits at their lowest
    /// and 300–500 nits at their highest level. Below this light, the image gets darker in software.
    var lowest = 0.1
    /// 1: the DDC level is linear in light output, which is typical.
    var gamma = 1.0
    /// The light the slider asks for is multiplied by this. Above 1 when the display follows a built-in display
    /// that is darker than it, so the two displays give the same light.
    var scale = 1.0

    func light(level: Double) -> Double {
        lowest + (1 - lowest) * pow(min(max(level, 0), 1), gamma)
    }

    /// The inverse of `light(level:)`.
    func level(light: Double) -> Double {
        pow(min(max((light - lowest) / (1 - lowest), 0), 1), 1 / gamma)
    }
}

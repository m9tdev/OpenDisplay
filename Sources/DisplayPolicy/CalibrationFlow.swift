import Foundation

/// The steps of the brightness calibration window, and the matches the user made so far.
///
/// With DDC: lowest → top → middle → middleReference → result. Without DDC, the external display can only get darker
/// in software, and that curve is known, so only top → result. Every change goes through `handle`, and the window
/// sets both displays to `levels` after each one.
public struct CalibrationFlow: Equatable, Sendable {
    public enum Step: CaseIterable, Equatable, Sendable {
        case lowest, top, middle, middleReference, result
    }

    /// The match at the highest brightness. The brighter display's slider belongs to its choice, so another choice
    /// starts at the highest level.
    public enum Top: Equatable, Sendable {
        /// The user has not selected the brighter display yet. Only on the top step: Next waits for a choice.
        case unchosen
        case same
        /// - Parameter slider: The built-in display's slider position that looks the same as the external display.
        case builtinBrighter(slider: Double)
        /// - Parameter slider: The external display's slider position (with DDC: its DDC level) that looks the same
        ///   as the built-in display.
        case externalBrighter(slider: Double)
    }

    public enum Event: Equatable, Sendable {
        case next
        case back
        /// To the first step, with the brighter display unchosen. The other matches stay.
        case startAgain
        /// Selects the brighter display on the top step.
        case choose(CalibrationTop.Brighter)
        /// Moves the slider of the current step.
        case move(Double)
    }

    /// The display a slider changes.
    public enum Side: Equatable, Sendable {
        case builtin, external
    }

    /// False: the external display has no DDC, so the calibration dims it in software.
    public let usesDDC: Bool
    /// The position in `steps`, so the step is always one of this calibration's steps.
    private var index = 0
    /// The built-in display's slider position that looks the same as the external display at its lowest DDC level.
    public private(set) var lowestSlider = BrightnessCurve.slider(light: ExternalCurve().lowest)
    public private(set) var top = Top.unchosen
    /// The external display's DDC level that looks the same as the built-in display at 50%.
    public private(set) var middleLevel = 0.2
    /// The built-in display's slider position that looks the same as the external display at the middle DDC level.
    public private(set) var middleReferenceSlider = 0.5

    public init(usesDDC: Bool) {
        self.usesDDC = usesDDC
    }

    public var steps: [Step] {
        usesDDC ? Step.allCases : [.top, .result]
    }

    public var step: Step { steps[index] }
    public var isFirstStep: Bool { index == 0 }
    /// From 1.
    public var stepNumber: Int { index + 1 }
    /// Without the result.
    public var stepCount: Int { steps.count - 1 }

    public mutating func handle(_ event: Event) {
        switch event {
        case .next:
            guard canGoOn, index + 1 < steps.count else { return }
            index += 1
        case .back:
            guard index > 0 else { return }
            index -= 1
        case .startAgain:
            top = .unchosen
            index = 0
        case .choose(let brighter):
            guard step == .top, brighter != self.brighter else { return }
            // The other display moves now, so it starts at its highest level.
            top = switch brighter {
            case .same: .same
            case .builtin: .builtinBrighter(slider: 1)
            case .external: .externalBrighter(slider: 1)
            }
        case .move(let value):
            // Inside the slider's range, as the slider itself keeps it: at 0, for example, the maximum of a brighter
            // external display would be infinite (see `CalibrationTop.sliderRange`).
            guard let range = slider?.range else { return }
            let value = min(max(value, range.lowerBound), range.upperBound)
            switch step {
            case .lowest: lowestSlider = value
            case .top:
                switch top {
                case .builtinBrighter: top = .builtinBrighter(slider: value)
                case .externalBrighter: top = .externalBrighter(slider: value)
                case .unchosen, .same: break
                }
            case .middle: middleLevel = value
            case .middleReference: middleReferenceSlider = value
            case .result: break
            }
        }
    }

    /// The brighter display the user selected, or nil.
    public var brighter: CalibrationTop.Brighter? {
        switch top {
        case .unchosen: nil
        case .same: .same
        case .builtinBrighter: .builtin
        case .externalBrighter: .external
        }
    }

    /// False on the top step until the user selects the brighter display.
    public var canGoOn: Bool {
        step != .top || top != .unchosen
    }

    /// The slider of the current step: its position, its range and the display it changes. Nil if the step has none.
    public var slider: (value: Double, range: ClosedRange<Double>, side: Side)? {
        let builtinRange = 0.01...1.0
        switch step {
        case .lowest:
            return (lowestSlider, builtinRange, .builtin)
        case .top:
            switch top {
            case .builtinBrighter(let slider): return (slider, CalibrationTop.sliderRange(.builtin), .builtin)
            case .externalBrighter(let slider): return (slider, CalibrationTop.sliderRange(.external), .external)
            case .unchosen, .same: return nil
            }
        case .middle:
            return (middleLevel, 0...1, .external)
        case .middleReference:
            return (middleReferenceSlider, builtinRange, .builtin)
        case .result:
            return nil
        }
    }

    /// The levels of both displays for the current step, or nil on the result, which changes none.
    /// - builtin: The built-in display's slider position, on the macOS curve.
    /// - external: The external display's DDC level, 0...1. Without DDC: its slider position for software dimming.
    public var levels: (builtin: Double, external: Double)? {
        switch step {
        case .lowest:
            return (lowestSlider, 0)
        case .top:
            switch top {
            case .builtinBrighter(let slider): return (slider, 1)
            case .externalBrighter(let slider): return (1, slider)
            case .unchosen, .same: return (1, 1)
            }
        case .middle:
            return (0.5, middleLevel)
        case .middleReference:
            return (middleReferenceSlider, CalibrationMatches.middleReferenceLevel)
        case .result:
            return nil
        }
    }

    /// The calibration values from the matches. Without DDC, only the maximum. With DDC, this runs the fit, which
    /// takes a moment.
    public var result: (lowest: Double?, gamma: Double?, maximum: Double, error: Double) {
        guard usesDDC else {
            let slider: Double = switch top {
            case .builtinBrighter(let slider), .externalBrighter(let slider): slider
            case .unchosen, .same: 1
            }
            return (nil, nil, CalibrationTop.maximumWithoutDDC(brighter: brighter, slider: slider), 1)
        }
        let fit = matches.fit()
        return (fit.lowest, fit.gamma, fit.maximum, fit.error)
    }

    public var matches: CalibrationMatches {
        let top: CalibrationMatches.Top = switch top {
        case .builtinBrighter(let slider): .builtinBrighter(light: BrightnessCurve.light(slider: slider))
        case .externalBrighter(let slider): .externalBrighter(level: slider)
        // Not reached past the top step: Next waits for a choice.
        case .same, .unchosen: .same
        }
        return CalibrationMatches(
            lowest: BrightnessCurve.light(slider: lowestSlider),
            top: top,
            middleLevel: middleLevel,
            middleReferenceLight: BrightnessCurve.light(slider: middleReferenceSlider))
    }
}

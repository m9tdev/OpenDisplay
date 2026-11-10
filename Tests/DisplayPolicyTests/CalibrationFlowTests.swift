import DisplayPolicy
import XCTest

/// The steps of the calibration window: which steps there are, where each event leads, and the levels and the result
/// each step gives.
final class CalibrationFlowTests: XCTestCase {
    private typealias Step = CalibrationFlow.Step

    private func flow(usesDDC: Bool, _ events: CalibrationFlow.Event...) -> CalibrationFlow {
        var flow = CalibrationFlow(usesDDC: usesDDC)
        events.forEach { flow.handle($0) }
        return flow
    }

    // MARK: Steps

    func testTheStepsWithAndWithoutDDC() {
        XCTAssertEqual(CalibrationFlow(usesDDC: true).steps, [.lowest, .top, .middle, .middleReference, .result])
        XCTAssertEqual(CalibrationFlow(usesDDC: false).steps, [.top, .result])
    }

    func testItStartsAtTheFirstStepWithNothingChosen() {
        for usesDDC in [true, false] {
            let flow = CalibrationFlow(usesDDC: usesDDC)
            XCTAssertEqual(flow.step, flow.steps[0])
            XCTAssertTrue(flow.isFirstStep)
            XCTAssertEqual(flow.stepNumber, 1)
            XCTAssertEqual(flow.stepCount, flow.steps.count - 1)
            XCTAssertEqual(flow.top, .unchosen)
            XCTAssertNil(flow.brighter)
        }
    }

    func testNextGoesThroughEveryStepInOrderAndStopsAtTheResult() {
        for usesDDC in [true, false] {
            var flow = CalibrationFlow(usesDDC: usesDDC)
            var visited = [flow.step]
            for _ in 0..<10 {
                if flow.step == .top { flow.handle(.choose(.same)) }
                flow.handle(.next)
                if visited.last != flow.step { visited.append(flow.step) }
            }
            XCTAssertEqual(visited, flow.steps, "DDC \(usesDDC)")
            XCTAssertEqual(flow.step, .result)
            XCTAssertEqual(flow.stepNumber, flow.steps.count)
        }
    }

    func testBackGoesThroughEveryStepInReverseAndStopsAtTheFirst() {
        for usesDDC in [true, false] {
            var flow = self.flow(usesDDC: usesDDC, .choose(.same))
            while flow.step != .result {
                if flow.step == .top { flow.handle(.choose(.same)) }
                flow.handle(.next)
            }
            var visited = [flow.step]
            for _ in 0..<10 {
                flow.handle(.back)
                if visited.last != flow.step { visited.append(flow.step) }
            }
            XCTAssertEqual(visited, flow.steps.reversed(), "DDC \(usesDDC)")
            XCTAssertTrue(flow.isFirstStep)
        }
    }

    func testNextWaitsOnTheTopStepUntilTheBrighterDisplayIsChosen() {
        var flow = self.flow(usesDDC: true, .next)
        XCTAssertEqual(flow.step, .top)
        XCTAssertFalse(flow.canGoOn)
        flow.handle(.next)
        XCTAssertEqual(flow.step, .top)
        for brighter in [CalibrationTop.Brighter.builtin, .external, .same] {
            var chosen = flow
            chosen.handle(.choose(brighter))
            XCTAssertTrue(chosen.canGoOn)
            chosen.handle(.next)
            XCTAssertEqual(chosen.step, .middle, "\(brighter)")
        }
        // Without DDC the top step is the first.
        var withoutDDC = CalibrationFlow(usesDDC: false)
        withoutDDC.handle(.next)
        XCTAssertEqual(withoutDDC.step, .top)
    }

    func testEveryOtherStepCanGoOn() {
        var flow = CalibrationFlow(usesDDC: true)
        XCTAssertTrue(flow.canGoOn)
        flow.handle(.next)
        flow.handle(.choose(.builtin))
        flow.handle(.next)
        XCTAssertTrue(flow.canGoOn)
        flow.handle(.next)
        XCTAssertTrue(flow.canGoOn)
    }

    func testNoStepPastTheTopHasTheBrighterDisplayUnchosen() {
        // Every sequence of up to 6 events from the start: past the top step, a choice was always made.
        let events: [CalibrationFlow.Event] = [.next, .back, .startAgain, .choose(.builtin), .choose(.same), .move(0.4)]
        for usesDDC in [true, false] {
            var flows = [CalibrationFlow(usesDDC: usesDDC)]
            for _ in 0..<6 {
                flows = flows.flatMap { flow in
                    events.map { event in
                        var next = flow
                        next.handle(event)
                        return next
                    }
                }
                for flow in flows {
                    let topIndex = flow.steps.firstIndex(of: .top)!
                    if flow.steps.firstIndex(of: flow.step)! > topIndex {
                        XCTAssertNotEqual(flow.top, .unchosen)
                    }
                    XCTAssertTrue(flow.steps.contains(flow.step))
                }
            }
        }
    }

    func testStartAgainGoesToTheFirstStepAndForgetsOnlyTheBrighterDisplay() {
        for usesDDC in [true, false] {
            var flow = CalibrationFlow(usesDDC: usesDDC)
            if usesDDC {
                flow.handle(.move(0.3))
                flow.handle(.next)
            }
            flow.handle(.choose(.external))
            flow.handle(.move(0.6))
            flow.handle(.next)
            if usesDDC {
                flow.handle(.move(0.7))
                flow.handle(.next)
                flow.handle(.move(0.8))
                flow.handle(.next)
            }
            XCTAssertEqual(flow.step, .result)
            flow.handle(.startAgain)
            XCTAssertEqual(flow.step, flow.steps[0])
            XCTAssertEqual(flow.top, .unchosen)
            if usesDDC {
                XCTAssertEqual(flow.lowestSlider, 0.3)
                XCTAssertEqual(flow.middleLevel, 0.7)
                XCTAssertEqual(flow.middleReferenceSlider, 0.8)
            }
        }
    }

    // MARK: The top step

    func testChoosingAnotherDisplayStartsItsSliderAtTheHighestLevel() {
        var flow = self.flow(usesDDC: false, .choose(.builtin), .move(0.4))
        XCTAssertEqual(flow.top, .builtinBrighter(slider: 0.4))
        flow.handle(.choose(.external))
        XCTAssertEqual(flow.top, .externalBrighter(slider: 1))
        flow.handle(.move(0.3))
        flow.handle(.choose(.same))
        XCTAssertEqual(flow.top, .same)
        flow.handle(.choose(.builtin))
        XCTAssertEqual(flow.top, .builtinBrighter(slider: 1))
    }

    func testChoosingTheSameDisplayAgainKeepsItsSlider() {
        var flow = self.flow(usesDDC: false, .choose(.external), .move(0.4))
        flow.handle(.choose(.external))
        XCTAssertEqual(flow.top, .externalBrighter(slider: 0.4))
    }

    func testTheBrighterDisplayFollowsTheChoice() {
        XCTAssertEqual(flow(usesDDC: false, .choose(.builtin)).brighter, .builtin)
        XCTAssertEqual(flow(usesDDC: false, .choose(.external)).brighter, .external)
        XCTAssertEqual(flow(usesDDC: false, .choose(.same)).brighter, .same)
    }

    func testChoosingOffTheTopStepChangesNothing() {
        let start = CalibrationFlow(usesDDC: true)
        var flow = start
        flow.handle(.choose(.builtin))
        XCTAssertEqual(flow, start)
    }

    // MARK: Sliders and levels

    func testTheSliderAndTheLevelsOfEachStepWithDDC() {
        var flow = CalibrationFlow(usesDDC: true)

        flow.handle(.move(0.3))
        XCTAssertEqual(flow.slider?.value, 0.3)
        XCTAssertEqual(flow.slider?.range, 0.01...1)
        XCTAssertEqual(flow.slider?.side, .builtin)
        XCTAssertEqual(flow.levels?.builtin, 0.3)
        XCTAssertEqual(flow.levels?.external, 0)

        flow.handle(.next)
        XCTAssertNil(flow.slider)
        XCTAssertEqual(flow.levels?.builtin, 1)
        XCTAssertEqual(flow.levels?.external, 1)
        flow.handle(.move(0.5))
        XCTAssertEqual(flow.top, .unchosen)
        flow.handle(.choose(.same))
        XCTAssertNil(flow.slider)
        XCTAssertEqual(flow.levels?.builtin, 1)
        XCTAssertEqual(flow.levels?.external, 1)
        flow.handle(.choose(.builtin))
        flow.handle(.move(0.6))
        XCTAssertEqual(flow.slider?.value, 0.6)
        XCTAssertEqual(flow.slider?.range, CalibrationTop.sliderRange(.builtin))
        XCTAssertEqual(flow.slider?.side, .builtin)
        XCTAssertEqual(flow.levels?.builtin, 0.6)
        XCTAssertEqual(flow.levels?.external, 1)
        flow.handle(.choose(.external))
        flow.handle(.move(0.7))
        XCTAssertEqual(flow.slider?.value, 0.7)
        XCTAssertEqual(flow.slider?.range, CalibrationTop.sliderRange(.external))
        XCTAssertEqual(flow.slider?.side, .external)
        XCTAssertEqual(flow.levels?.builtin, 1)
        XCTAssertEqual(flow.levels?.external, 0.7)

        flow.handle(.next)
        XCTAssertEqual(flow.slider?.value, 0.2)
        flow.handle(.move(0.4))
        XCTAssertEqual(flow.slider?.range, 0...1)
        XCTAssertEqual(flow.slider?.side, .external)
        XCTAssertEqual(flow.levels?.builtin, 0.5)
        XCTAssertEqual(flow.levels?.external, 0.4)

        flow.handle(.next)
        XCTAssertEqual(flow.slider?.value, 0.5)
        flow.handle(.move(0.45))
        XCTAssertEqual(flow.slider?.range, 0.01...1)
        XCTAssertEqual(flow.slider?.side, .builtin)
        XCTAssertEqual(flow.levels?.builtin, 0.45)
        XCTAssertEqual(flow.levels?.external, CalibrationMatches.middleReferenceLevel)

        flow.handle(.next)
        XCTAssertNil(flow.slider)
        XCTAssertNil(flow.levels)
        let before = flow
        flow.handle(.move(0.9))
        XCTAssertEqual(flow, before)

        // Back shows each match again.
        flow.handle(.back)
        XCTAssertEqual(flow.slider?.value, 0.45)
        flow.handle(.back)
        XCTAssertEqual(flow.slider?.value, 0.4)
        flow.handle(.back)
        XCTAssertEqual(flow.top, .externalBrighter(slider: 0.7))
        flow.handle(.back)
        XCTAssertEqual(flow.slider?.value, 0.3)
    }

    func testTheLowestStepStartsAtTheEstimatedLowestLight() {
        let flow = CalibrationFlow(usesDDC: true)
        XCTAssertEqual(flow.slider?.value, BrightnessCurve.slider(light: ExternalCurve().lowest))
    }

    // MARK: Result

    func testTheResultWithoutDDCIsTheMaximumOfTheTopStep() {
        for (events, brighter, slider) in [
            ([CalibrationFlow.Event.choose(.builtin), .move(0.5)], CalibrationTop.Brighter.builtin, 0.5),
            ([.choose(.external), .move(0.5)], .external, 0.5),
            ([.choose(.external), .move(0)], .external, 0),
            ([.choose(.same)], .same, 1),
        ] as [([CalibrationFlow.Event], CalibrationTop.Brighter, Double)] {
            var flow = CalibrationFlow(usesDDC: false)
            events.forEach { flow.handle($0) }
            flow.handle(.next)
            XCTAssertEqual(flow.step, .result)
            let result = flow.result
            XCTAssertNil(result.lowest)
            XCTAssertNil(result.gamma)
            XCTAssertEqual(result.error, 1)
            XCTAssertEqual(result.maximum, CalibrationTop.maximumWithoutDDC(brighter: brighter, slider: slider))
            XCTAssertTrue(CalibrationPolicy.isUsable(maximum: result.maximum))
        }
    }

    func testTheMatchesFollowTheSliders() {
        var flow = CalibrationFlow(usesDDC: true)
        flow.handle(.move(0.3))
        flow.handle(.next)
        flow.handle(.choose(.builtin))
        flow.handle(.move(0.6))
        flow.handle(.next)
        flow.handle(.move(0.4))
        flow.handle(.next)
        flow.handle(.move(0.45))
        XCTAssertEqual(flow.matches, CalibrationMatches(
            lowest: BrightnessCurve.light(slider: 0.3), top: .builtinBrighter(light: BrightnessCurve.light(slider: 0.6)),
            middleLevel: 0.4, middleReferenceLight: BrightnessCurve.light(slider: 0.45)))
        flow.handle(.back)
        flow.handle(.back)
        flow.handle(.choose(.external))
        flow.handle(.move(0.8))
        XCTAssertEqual(flow.matches.top, .externalBrighter(level: 0.8))
        flow.handle(.choose(.same))
        XCTAssertEqual(flow.matches.top, .same)
    }

    func testTheFitFindsTheCurveOfExactMatches() {
        // Matches by a perfect eye on a display with a known curve.
        let curve = ExternalCurve(lowest: 0.05, gamma: 2)
        let maximum = 0.8
        let matches = CalibrationMatches(
            lowest: maximum * curve.lowest,
            top: .builtinBrighter(light: maximum),
            middleLevel: curve.level(light: CalibrationMatches.middleLight / maximum),
            middleReferenceLight: maximum * curve.light(level: CalibrationMatches.middleReferenceLevel))
        let fit = matches.fit()
        XCTAssertEqual(fit.lowest, 0.05, accuracy: 0.05 * 0.04)
        XCTAssertEqual(fit.gamma, 2, accuracy: 2 * 0.02)
        XCTAssertEqual(fit.maximum, 0.8, accuracy: 0.8 * 0.04)
        XCTAssertLessThan(fit.error, 1.03)
    }

    func testTheFitIsUsableAtTheEndsOfEverySlider() {
        for top in [CalibrationMatches.Top.same, .builtinBrighter(light: BrightnessCurve.light(slider: 0.01)),
                    .builtinBrighter(light: 1), .externalBrighter(level: 0.01), .externalBrighter(level: 1)] {
            for (lowest, middle, reference) in [(0.01, 0.0, 0.01), (1.0, 1.0, 1.0)] {
                let fit = CalibrationMatches(
                    lowest: BrightnessCurve.light(slider: lowest), top: top, middleLevel: middle,
                    middleReferenceLight: BrightnessCurve.light(slider: reference)).fit()
                XCTAssertTrue(CalibrationPolicy.isUsable(maximum: fit.maximum), "\(top) \(lowest) \(middle) \(reference)")
                XCTAssertTrue(fit.error.isFinite)
            }
        }
    }
}

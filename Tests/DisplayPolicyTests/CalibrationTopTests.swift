import DisplayPolicy
import XCTest

/// The step at the highest brightness: the result must be a light the app can show and save, wherever the slider is.
final class CalibrationTopTests: XCTestCase {
    private let moving: [CalibrationTop.Brighter] = [.builtin, .external]

    func testNeitherSliderReachesZero() {
        // At 0 the light is 0, which matches nothing: the built-in display turns black.
        for brighter in moving {
            XCTAssertGreaterThan(CalibrationTop.sliderRange(brighter).lowerBound, 0, "\(brighter)")
        }
    }

    func testTheMaximumIsALightAtTheLowestSliderPositions() {
        for brighter in moving {
            for slider in [CalibrationTop.sliderRange(brighter).lowerBound, 0] {
                let maximum = CalibrationTop.maximumWithoutDDC(brighter: brighter, slider: slider)
                XCTAssertTrue(maximum.isFinite, "\(brighter) at \(slider): \(maximum)")
                XCTAssertGreaterThan(maximum, 0, "\(brighter) at \(slider)")
            }
        }
    }

    func testASliderBelowItsRangeCountsAsItsLowestPosition() {
        for brighter in moving {
            let lowest = CalibrationTop.sliderRange(brighter).lowerBound
            XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: brighter, slider: 0),
                           CalibrationTop.maximumWithoutDDC(brighter: brighter, slider: lowest), "\(brighter)")
        }
    }

    func testTheMaximumFollowsTheMatch() {
        XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: .same, slider: 0.3), 1)
        XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: nil, slider: 0.3), 1)
        XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: .builtin, slider: 1), 1)
        XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: .external, slider: 1), 1)
        // The built-in display matched at half its slider: the external display has 0.28 of its light.
        XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: .builtin, slider: 0.5), 0.28, accuracy: 1e-9)
        // The external display matched at half its slider: it has 1 / 0.28 of the built-in display's light.
        XCTAssertEqual(CalibrationTop.maximumWithoutDDC(brighter: .external, slider: 0.5), 1 / 0.28, accuracy: 1e-9)
    }
}

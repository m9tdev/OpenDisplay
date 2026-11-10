import DisplayPolicy
import XCTest

/// When macOS does not let the app dim a display in software, the display is not dimmed: the slider shows the light it
/// really gives, and the menu shows an error.
final class DimmingOutcomeTests: XCTestCase {
    let software = BrightnessControl.software(scale: 1)
    let external = BrightnessControl.external(ExternalCurve())

    // MARK: The dimming worked or was not needed

    func testADimmedDisplayKeepsItsSliderAndHasNoError() {
        let (_, dimming) = software.split(0.3)
        let outcome = DimmingOutcome(control: software, slider: 0.3, dimming: dimming, dimmed: true)
        XCTAssertEqual(outcome.slider, 0.3)
        XCTAssertEqual(outcome.dimming, dimming)
        XCTAssertNil(outcome.error)
    }

    func testNoDimmingNeededIsNoError() {
        // Above its lowest level, an external display needs no software dimming.
        let (level, dimming) = external.split(0.8)
        XCTAssertNotNil(level)
        XCTAssertEqual(dimming, 1)
        let outcome = DimmingOutcome(control: external, slider: 0.8, dimming: dimming, dimmed: false)
        XCTAssertEqual(outcome.slider, 0.8)
        XCTAssertEqual(outcome.dimming, 1)
        XCTAssertNil(outcome.error)
    }

    // MARK: macOS did not dim the display

    func testADisplayWithoutDDCThatCannotBeDimmedShowsFullBrightness() {
        let (_, dimming) = software.split(0.3)
        XCTAssertLessThan(dimming, 1)
        let outcome = DimmingOutcome(control: software, slider: 0.3, dimming: dimming, dimmed: false)
        // Software dimming is its only control, so the display gives its full light.
        XCTAssertEqual(outcome.slider, 1)
        XCTAssertEqual(outcome.dimming, 1)
        XCTAssertEqual(outcome.error, DimmingOutcome.failureMessage)
    }

    func testASyncedDisplayWithoutDDCThatCannotBeDimmedShowsItsMaximum() {
        // A synced display that is not the brightest: its light is twice the slider's.
        let synced = BrightnessControl.software(scale: 2)
        let (_, dimming) = synced.split(0.3)
        let outcome = DimmingOutcome(control: synced, slider: 0.3, dimming: dimming, dimmed: false)
        XCTAssertEqual(outcome.slider!, BrightnessCurve.slider(light: 0.5), accuracy: 1e-9)
        XCTAssertEqual(outcome.dimming, 1)
        XCTAssertEqual(outcome.error, DimmingOutcome.failureMessage)
    }

    func testAnExternalDisplayThatCannotBeDimmedShowsItsLowestLevel() {
        // Below its lowest level: DDC level 0, and software dimming for the rest.
        let (level, dimming) = external.split(0.2)
        XCTAssertEqual(level, 0)
        XCTAssertLessThan(dimming, 1)
        let outcome = DimmingOutcome(control: external, slider: 0.2, dimming: dimming, dimmed: false)
        // The DDC level still works: the display is at its lowest level, without the dimming.
        XCTAssertEqual(outcome.slider!, external.slider(level: 0, dimming: 1), accuracy: 1e-9)
        XCTAssertGreaterThan(outcome.slider!, 0.2)
        XCTAssertEqual(outcome.dimming, 1)
        XCTAssertEqual(outcome.error, DimmingOutcome.failureMessage)
        // The shown position asks for the lowest level, and no real dimming.
        let shown = external.split(outcome.slider!)
        XCTAssertEqual(shown.level!, 0, accuracy: 1e-6)
        XCTAssertEqual(shown.dimming, 1, accuracy: 1e-6)
    }

    func testADimmingWithoutAKnownSliderStillFails() {
        // A display that came back gets its old dimming before its brightness is read.
        let outcome = DimmingOutcome(control: software, slider: nil, dimming: 0.2, dimmed: false)
        XCTAssertNil(outcome.slider)
        XCTAssertEqual(outcome.dimming, 1)
        XCTAssertEqual(outcome.error, DimmingOutcome.failureMessage)
    }

    func testAWorkingDimmingAfterAFailureClearsTheError() {
        let failed = DimmingOutcome(control: software, slider: 0.3, dimming: 0.04, dimmed: false)
        XCTAssertNotNil(failed.error)
        let worked = DimmingOutcome(control: software, slider: 0.3, dimming: 0.04, dimmed: true)
        XCTAssertNil(worked.error)
        XCTAssertEqual(worked.dimming, 0.04)
    }
}

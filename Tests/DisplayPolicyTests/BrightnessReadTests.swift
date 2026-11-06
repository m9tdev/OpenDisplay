import DisplayPolicy
import XCTest

/// The brightness slider shows what the hardware gives after a read, and stays where it is when the hardware is as the
/// slider set it.
final class BrightnessReadTests: XCTestCase {
    /// A synced display that is not the brightest: its light is twice the slider's, up to its maximum.
    let synced = BrightnessControl.external(ExternalCurve(scale: 2))
    let syncedWithoutDDC = BrightnessControl.software(scale: 2)

    // MARK: A synced display near the top of its range

    func testASyncedDisplayAtItsMaximumKeepsItsSliderAfterARead() {
        // From about 0.73 up, the display is at its maximum: the hardware cannot tell those positions apart.
        let shown = 0.95
        let (level, dimming) = synced.split(shown)
        XCTAssertEqual(level, 1)
        XCTAssertEqual(synced.slider(readLevel: level, dimming: dimming, shown: shown, levelStep: 0.01), shown)
    }

    func testASyncedDisplayWithoutDDCKeepsItsSliderAfterARead() {
        let shown = 0.95
        let (level, dimming) = syncedWithoutDDC.split(shown)
        XCTAssertEqual(syncedWithoutDDC.slider(readLevel: level, dimming: dimming, shown: shown, levelStep: 0), shown)
    }

    func testTheSliderKeepsItsPositionWhenTheMonitorRoundsTheLevel() {
        let control = BrightnessControl.external(ExternalCurve())
        let shown = 0.6
        let level = (control.split(shown).level! * 100).rounded() / 100
        XCTAssertEqual(control.slider(readLevel: level, dimming: 1, shown: shown, levelStep: 0.01), shown)
    }

    func testAChangedLevelMovesTheSlider() {
        // The monitor's own buttons changed it.
        let read = synced.slider(readLevel: 0.5, dimming: 1, shown: 0.95, levelStep: 0.01)
        XCTAssertEqual(read, synced.slider(level: 0.5, dimming: 1))
        XCTAssertLessThan(read, 0.95)
    }

    func testAReadWithoutAShownPositionMapsTheLevel() {
        XCTAssertEqual(synced.slider(readLevel: 0.5, dimming: 1, shown: nil, levelStep: 0.01),
                       synced.slider(level: 0.5, dimming: 1))
    }

    // MARK: Hardware brightness with software dimming

    func testRaisedHardwareBrightnessShowsWhileDimmed() {
        let control = BrightnessControl.external(ExternalCurve())
        let dimmed = 0.1
        let (level, dimming) = control.split(dimmed)
        XCTAssertEqual(level, 0)
        XCTAssertLessThan(dimming, 1)
        // The monitor's buttons raise its level to 0.8; the image is still dimmed in software.
        let light = dimming * ExternalCurve().light(level: 0.8)
        let read = control.slider(readLevel: 0.8, dimming: dimming, shown: dimmed, levelStep: 0.01)
        XCTAssertEqual(read, BrightnessCurve.slider(light: light), accuracy: 1e-9)
        XCTAssertGreaterThan(read, dimmed)
    }

    func testTheLowestLevelWithDimmingGivesTheDimmedPosition() {
        let control = BrightnessControl.external(ExternalCurve())
        let dimmed = 0.1
        let (_, dimming) = control.split(dimmed)
        XCTAssertEqual(control.slider(level: 0, dimming: dimming), dimmed, accuracy: 1e-9)
    }
}

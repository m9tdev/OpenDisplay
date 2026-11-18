import DisplayPolicy
import XCTest

/// A display mode the menu showed, applied after the display's modes may have changed.
final class DisplayModeChoiceTests: XCTestCase {
    func mode(_ id: Int32, _ width: Int, _ height: Int, pixelWidth: Int? = nil, rate: Double = 60) -> DisplayModeChoice.Mode {
        .init(id: id, width: width, height: height, pixelWidth: pixelWidth ?? width * 2, refreshRate: rate)
    }

    func testAModeTheDisplayStillOffersApplies() {
        let chosen = mode(7, 1920, 1080)
        XCTAssertNil(DisplayModeChoice.unavailable(chosen, offered: [mode(3, 2560, 1440), chosen]))
    }

    func testARefreshRateThatDiffersOnlyByRoundingApplies() {
        XCTAssertNil(DisplayModeChoice.unavailable(mode(7, 1920, 1080, rate: 59.94),
                                                   offered: [mode(7, 1920, 1080, rate: 59.9401)]))
    }

    func testAModeTheDisplayNoLongerOffersFails() {
        let error = DisplayModeChoice.unavailable(mode(7, 1920, 1080), offered: [mode(3, 2560, 1440)])
        XCTAssertEqual(error, DisplayModeChoice.unavailableMessage)
    }

    func testADisplayWithoutModesFails() {
        // For example a display that turned off or went away after the menu showed its modes.
        XCTAssertEqual(DisplayModeChoice.unavailable(mode(7, 1920, 1080), offered: []), DisplayModeChoice.unavailableMessage)
    }

    func testTheSameModeIDWithAnotherSizeFails() {
        // Another monitor can get the display ID, and its modes their own meaning for the same mode ID.
        XCTAssertNotNil(DisplayModeChoice.unavailable(mode(7, 1920, 1080), offered: [mode(7, 1280, 720)]))
        XCTAssertNotNil(DisplayModeChoice.unavailable(mode(7, 1920, 1080), offered: [mode(7, 1920, 1080, pixelWidth: 1920)]))
        XCTAssertNotNil(DisplayModeChoice.unavailable(mode(7, 1920, 1080), offered: [mode(7, 1920, 1080, rate: 30)]))
    }

    func testTheSameSizeWithAnotherModeIDFails() {
        XCTAssertNotNil(DisplayModeChoice.unavailable(mode(7, 1920, 1080), offered: [mode(8, 1920, 1080)]))
    }
}

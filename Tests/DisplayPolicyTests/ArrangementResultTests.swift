import DisplayPolicy
import XCTest

/// A change of the main display or of a rotation reports what macOS did, not success regardless.
final class ArrangementResultTests: XCTestCase {
    // MARK: Main display

    func testADisplayListThatWasReadIsNoError() {
        XCTAssertNil(ArrangementResult.displayListError(result: 0, count: 2))
    }

    func testADisplayListThatFailedIsAnError() {
        // kCGErrorFailure: before, the empty list gave an empty configuration that "succeeded".
        XCTAssertEqual(ArrangementResult.displayListError(result: 1000, count: 0),
                       "Could not read the displays (error 1000).")
    }

    func testAnEmptyDisplayListIsAnError() {
        // Moving no display changes nothing, so it cannot make a display the main display.
        XCTAssertEqual(ArrangementResult.displayListError(result: 0, count: 0), "Could not read the displays.")
    }

    func testDisplaysThatAllMovedAreNoError() {
        XCTAssertNil(ArrangementResult.originError(results: [0, 0, 0]))
        XCTAssertNil(ArrangementResult.originError(results: []))
    }

    func testADisplayThatDidNotMoveIsAnError() {
        // kCGErrorIllegalArgument for the second display.
        XCTAssertEqual(ArrangementResult.originError(results: [0, 1001, 0]),
                       "Could not change the main display (error 1001).")
    }

    func testTheFirstFailureIsShown() {
        XCTAssertEqual(ArrangementResult.originError(results: [1004, 1001]),
                       "Could not change the main display (error 1004).")
    }

    func testDisplaysThatMirrorNoOtherAreMoved() {
        XCTAssertEqual(ArrangementResult.displaysToMove([(id: 1, mirrors: 0), (id: 5, mirrors: 0)]), [1, 5])
    }

    func testADisplayThatMirrorsAnotherIsNotMoved() {
        // Its master positions it; moving it may fail, and that would cancel the whole change every time.
        XCTAssertEqual(ArrangementResult.displaysToMove([(id: 1, mirrors: 0), (id: 5, mirrors: 1), (id: 7, mirrors: 0)]),
                       [1, 7])
    }

    // MARK: Rotation

    func testTheRotationAskedForIsNoError() {
        for degrees in [0, 90, 180, 270] {
            XCTAssertNil(ArrangementResult.rotationError(requested: degrees, readBack: Double(degrees)))
        }
    }

    func testARotationReadWithRoundingIsNoError() {
        XCTAssertNil(ArrangementResult.rotationError(requested: 90, readBack: 89.9999))
        XCTAssertNil(ArrangementResult.rotationError(requested: 0, readBack: 359.9999))
    }

    func testAnotherRotationIsAnError() {
        // The private call returns nothing: the read-back is the only sign that macOS did not rotate the display.
        XCTAssertEqual(ArrangementResult.rotationError(requested: 90, readBack: 0),
                       "Could not rotate the display to 90°.")
        XCTAssertEqual(ArrangementResult.rotationError(requested: 0, readBack: 270),
                       "Could not rotate the display to 0°.")
    }
}

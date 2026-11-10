import DisplayPolicy
import XCTest

final class SliderGestureTests: XCTestCase {
    func testTheOldValueThatAppKitSendsAtMouseDownIsNotAMove() {
        var gesture = SliderGesture.pressed(at: 3)
        XCTAssertFalse(gesture.moved(to: 3))
        XCTAssertEqual(gesture, .pressed(at: 3))
        // Then the clicked position on the track.
        XCTAssertTrue(gesture.moved(to: 1.77))
        XCTAssertEqual(gesture, .dragging)
    }

    func testADragKeepsMoving() {
        var gesture = SliderGesture.dragging
        XCTAssertTrue(gesture.moved(to: 3))
        XCTAssertTrue(gesture.moved(to: 3))
        XCTAssertEqual(gesture, .dragging)
    }

    func testASteppedSliderAppliesNothingWhileTheMouseIsDown() {
        XCTAssertNil(SliderGesture.pressed(at: 3).choice(1, current: 3))
        XCTAssertNil(SliderGesture.dragging.choice(1, current: 3))
    }

    func testASteppedSliderAppliesANewChoiceOnRelease() {
        XCTAssertEqual(SliderGesture.released(moved: true).choice(1, current: 3), 1)
        XCTAssertNil(SliderGesture.released(moved: true).choice(3, current: 3))
        // A display mode that is not in the list.
        XCTAssertEqual(SliderGesture.released(moved: true).choice(0, current: nil), 0)
    }

    func testAPressAndReleaseWithoutAMoveAppliesNothing() {
        // The current display mode is not in the list, so the knob shows an older choice.
        var gesture = SliderGesture.idle
        gesture.press(at: 2, isEnabled: true)
        XCTAssertFalse(gesture.moved(to: 2))
        XCTAssertTrue(gesture.release())
        XCTAssertEqual(gesture, .released(moved: false))
        XCTAssertNil(gesture.choice(2, current: nil))
    }

    func testAPressDragAndReleaseEndsMoved() {
        var gesture = SliderGesture.idle
        gesture.press(at: 2, isEnabled: true)
        XCTAssertTrue(gesture.moved(to: 1))
        XCTAssertTrue(gesture.release())
        XCTAssertEqual(gesture, .released(moved: true))
    }

    func testADisabledSliderHasNoGesture() {
        // A disabled slider in a menu still gets the mouse-down.
        var gesture = SliderGesture.idle
        gesture.press(at: 0, isEnabled: false)
        XCTAssertEqual(gesture, .idle)
        XCTAssertFalse(gesture.release())
        XCTAssertEqual(gesture, .idle)
    }

    func testWithoutAGestureANewChoiceAppliesAtOnce() {
        // The keyboard or VoiceOver.
        XCTAssertEqual(SliderGesture.idle.choice(2, current: 3), 2)
        XCTAssertNil(SliderGesture.idle.choice(3, current: 3))
    }

    func testTheKnobStaysUnderTheMouse() {
        XCTAssertFalse(SliderGesture.pressed(at: 3).followsStoredValue)
        XCTAssertFalse(SliderGesture.dragging.followsStoredValue)
        XCTAssertTrue(SliderGesture.released(moved: true).followsStoredValue)
        XCTAssertTrue(SliderGesture.idle.followsStoredValue)
    }
}

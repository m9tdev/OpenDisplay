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
        XCTAssertEqual(SliderGesture.released.choice(1, current: 3), 1)
        XCTAssertNil(SliderGesture.released.choice(3, current: 3))
        // A display mode that is not in the list.
        XCTAssertEqual(SliderGesture.released.choice(0, current: nil), 0)
    }

    func testWithoutAGestureANewChoiceAppliesAtOnce() {
        // The keyboard or VoiceOver.
        XCTAssertEqual(SliderGesture.idle.choice(2, current: 3), 2)
        XCTAssertNil(SliderGesture.idle.choice(3, current: 3))
    }

    func testTheKnobStaysUnderTheMouse() {
        XCTAssertFalse(SliderGesture.pressed(at: 3).followsStoredValue)
        XCTAssertFalse(SliderGesture.dragging.followsStoredValue)
        XCTAssertTrue(SliderGesture.released.followsStoredValue)
        XCTAssertTrue(SliderGesture.idle.followsStoredValue)
    }
}

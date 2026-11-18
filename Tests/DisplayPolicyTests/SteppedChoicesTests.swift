import DisplayPolicy
import XCTest

/// The list a stepped slider shows, while a refresh brings a new list.
final class SteppedChoicesTests: XCTestCase {
    func testWithoutAGestureANewListIsTaken() {
        var list = SteppedChoices<String>()
        XCTAssertTrue(list.update(["720p", "1080p"], current: 1, gesture: .idle))
        XCTAssertEqual(list.choices, ["720p", "1080p"])
        XCTAssertEqual(list.current, 1)
    }

    func testWhileTheKnobIsHeldTheShownListStays() {
        var list = SteppedChoices<String>()
        list.update(["720p", "1080p", "1440p"], current: 2, gesture: .idle)
        // A refresh while the knob is held: the knob shows a title of the old list.
        XCTAssertFalse(list.update(["1080p", "1440p"], current: 1, gesture: .pressed(at: 2)))
        XCTAssertFalse(list.update(["1080p", "1440p"], current: 1, gesture: .dragging))
        XCTAssertEqual(list.choices, ["720p", "1080p", "1440p"])
        XCTAssertEqual(list.current, 2)
    }

    func testReleaseAppliesTheChoiceTheKnobShows() {
        var list = SteppedChoices<String>()
        list.update(["720p", "1080p", "1440p"], current: 2, gesture: .idle)
        list.update(["1080p", "1440p"], current: 1, gesture: .dragging)
        XCTAssertEqual(list.choice(at: 0, gesture: .released(moved: true)), "720p")
    }

    func testTheCurrentChoiceDoesNotApplyAgain() {
        var list = SteppedChoices<String>()
        list.update(["720p", "1080p"], current: 1, gesture: .idle)
        XCTAssertNil(list.choice(at: 1, gesture: .released(moved: true)))
        XCTAssertEqual(list.choice(at: 0, gesture: .idle), "720p")
    }

    func testNothingAppliesWhileHeldOrOutsideTheList() {
        var list = SteppedChoices<String>()
        list.update(["720p", "1080p"], current: 1, gesture: .idle)
        XCTAssertNil(list.choice(at: 0, gesture: .dragging))
        XCTAssertNil(list.choice(at: 0, gesture: .released(moved: false)))
        XCTAssertNil(list.choice(at: 2, gesture: .released(moved: true)))
        XCTAssertNil(list.choice(at: -1, gesture: .released(moved: true)))
    }

    func testAfterReleaseANewListIsTaken() {
        var list = SteppedChoices<String>()
        list.update(["720p"], current: 0, gesture: .idle)
        XCTAssertTrue(list.update(["720p", "1080p"], current: 0, gesture: .released(moved: true)))
        XCTAssertEqual(list.choices, ["720p", "1080p"])
    }
}

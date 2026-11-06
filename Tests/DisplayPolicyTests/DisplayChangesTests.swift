import DisplayPolicy
import XCTest

/// On/off changes in progress: two quick clicks on one display, and a refresh while a display turns off.
final class DisplayChangesTests: XCTestCase {
    // MARK: One change

    func testAChangeIsInProgressUntilItEnds() {
        var changes = DisplayChanges()
        let change = changes.begin(2)
        XCTAssertTrue(changes.isChanging(2))
        XCTAssertFalse(changes.isEmpty)
        XCTAssertTrue(changes.end(change))
        XCTAssertFalse(changes.isChanging(2))
        XCTAssertTrue(changes.isEmpty)
    }

    func testChangesOfTwoDisplaysAreSeparate() {
        var changes = DisplayChanges()
        let first = changes.begin(2)
        let second = changes.begin(3)
        XCTAssertEqual(changes.count, 2)
        XCTAssertTrue(changes.end(first))
        XCTAssertFalse(changes.isChanging(2))
        XCTAssertTrue(changes.isChanging(3))
        XCTAssertTrue(changes.end(second))
        XCTAssertTrue(changes.isEmpty)
    }

    // MARK: Two quick changes of one display (a double-click on its on/off icon)

    func testTheDisplayIsChangingUntilTheLastOfTwoQuickChangesEnds() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        let on = changes.begin(2)
        _ = changes.end(off)
        // The refresh after the first change must not show its state: the second change is still running.
        XCTAssertTrue(changes.isChanging(2))
        XCTAssertFalse(changes.isEmpty)
        _ = changes.end(on)
        XCTAssertFalse(changes.isChanging(2))
        XCTAssertTrue(changes.isEmpty)
    }

    func testOnlyTheLastOfTwoQuickChangesIsTheLatest() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        let on = changes.begin(2)
        XCTAssertFalse(changes.end(off))
        XCTAssertTrue(changes.end(on))
    }

    func testOnlyTheLastOfThreeQuickChangesIsTheLatest() {
        var changes = DisplayChanges()
        let first = changes.begin(2), second = changes.begin(2), third = changes.begin(2)
        XCTAssertFalse(changes.end(first))
        XCTAssertTrue(changes.isChanging(2))
        XCTAssertFalse(changes.end(second))
        XCTAssertTrue(changes.isChanging(2))
        XCTAssertTrue(changes.end(third))
        XCTAssertFalse(changes.isChanging(2))
    }

    func testAnEarlierChangeThatEndsLastIsNotTheLatest() {
        var changes = DisplayChanges()
        let first = changes.begin(2)
        let second = changes.begin(2)
        XCTAssertTrue(changes.end(second))
        XCTAssertTrue(changes.isChanging(2))
        XCTAssertFalse(changes.end(first))
        XCTAssertFalse(changes.isChanging(2))
    }

    func testANewChangeAfterTheOthersEndedIsTheLatest() {
        var changes = DisplayChanges()
        let first = changes.begin(2), second = changes.begin(2)
        _ = changes.end(first)
        _ = changes.end(second)
        let third = changes.begin(2)
        XCTAssertTrue(changes.end(third))
        XCTAssertTrue(changes.isEmpty)
    }

    func testAChangeEndedTwiceDoesNotEndTheNextOne() {
        var changes = DisplayChanges()
        let first = changes.begin(2)
        _ = changes.end(first)
        let second = changes.begin(2)
        XCTAssertFalse(changes.end(first))
        XCTAssertTrue(changes.isChanging(2))
        XCTAssertTrue(changes.end(second))
        XCTAssertFalse(changes.isChanging(2))
    }

    // MARK: Errors

    func testTheErrorOfTheLatestChangeIsShown() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        XCTAssertEqual(changes.end(off, error: "Could not turn off"),
                       DisplayChanges.Outcome(isLatest: true, shownError: "Could not turn off"))
    }

    func testAChangeThatWorkedShowsNoError() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        XCTAssertEqual(changes.end(off, error: nil), DisplayChanges.Outcome(isLatest: true))
    }

    func testTheErrorOfAnEarlierChangeIsNotShown() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        let on = changes.begin(2)
        // The later change sets what the app shows, and it may work.
        XCTAssertEqual(changes.end(off, error: "Could not turn off"), DisplayChanges.Outcome(isLatest: false))
        XCTAssertEqual(changes.end(on, error: nil), DisplayChanges.Outcome(isLatest: true))
    }

    func testTheErrorOfTheLaterChangeIsShownAfterAnEarlierOneFailed() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        let on = changes.begin(2)
        _ = changes.end(off, error: "Could not turn off")
        XCTAssertEqual(changes.end(on, error: "Could not turn on"),
                       DisplayChanges.Outcome(isLatest: true, shownError: "Could not turn on"))
    }

    func testTheErrorOfAnotherDisplaysChangeIsShown() {
        var changes = DisplayChanges()
        let first = changes.begin(2)
        _ = changes.begin(3)
        XCTAssertEqual(changes.end(first, error: "Could not turn off"),
                       DisplayChanges.Outcome(isLatest: true, shownError: "Could not turn off"))
    }

    // MARK: A refresh while a display turns off

    func testADisplayTurningOffStaysListedWhenMacOSNoLongerListsIt() {
        var changes = DisplayChanges()
        _ = changes.begin(2)
        XCTAssertEqual(changes.listed([1], before: [1, 2]), [1, 2])
    }

    func testADisplayStaysListedUntilTheLastOfTwoQuickChangesEnds() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        _ = changes.begin(2)
        _ = changes.end(off)
        XCTAssertEqual(changes.listed([1], before: [1, 2]), [1, 2])
    }

    func testListedKeepsTheOrderAndAddsNoDuplicates() {
        var changes = DisplayChanges()
        _ = changes.begin(2)
        _ = changes.begin(3)
        _ = changes.begin(4)
        XCTAssertEqual(changes.listed([4, 1], before: [1, 3, 2, 4]), [4, 1, 3, 2])
    }

    func testADisplayGoesFromTheListOnceItsChangeEnded() {
        var changes = DisplayChanges()
        let off = changes.begin(2)
        _ = changes.end(off)
        XCTAssertEqual(changes.listed([1], before: [1, 2]), [1])
    }

    func testADisplayThatWasNotListedIsNotAdded() {
        var changes = DisplayChanges()
        _ = changes.begin(5)
        XCTAssertEqual(changes.listed([1], before: [1, 2]), [1])
    }
}

import DisplayPolicy
import XCTest

/// The menu's errors, one slot per source: each source sets and clears only its own error, and the menu shows them
/// all as one text.
final class ErrorSlotsTests: XCTestCase {
    let restoreError = "Could not turn on Built-in Retina Display (error 1001)."
    let actionError = "Could not change the resolution."

    func testNoErrorShowsNothing() {
        XCTAssertNil(ErrorSlots().text)
    }

    func testOneErrorShowsAsItIs() {
        var errors = ErrorSlots()
        errors[.action] = actionError
        XCTAssertEqual(errors.text, actionError)
        XCTAssertEqual(errors[.action], actionError)
        XCTAssertNil(errors[.restore])
    }

    func testTheStartOfAnActionKeepsTheRestoreError() {
        // A failed attempt to turn a display on again, then the user turns a display on or off: the action clears its
        // own error at its start, not the error of the failed attempt.
        var errors = ErrorSlots()
        errors[.restore] = restoreError
        errors[.action] = nil
        XCTAssertEqual(errors.text, restoreError)
    }

    func testClearingTheRestoreErrorKeepsTheErrorOfAnAction() {
        // A display is on again: the restore error is stale, a failed resolution change is not.
        var errors = ErrorSlots()
        errors[.restore] = restoreError
        errors[.action] = actionError
        errors[.restore] = nil
        XCTAssertEqual(errors.text, actionError)
    }

    func testAnActionErrorDoesNotReplaceTheRestoreError() {
        var errors = ErrorSlots()
        errors[.restore] = restoreError
        errors[.action] = actionError
        XCTAssertEqual(errors[.restore], restoreError)
        XCTAssertEqual(errors[.action], actionError)
    }

    func testAllErrorsShowInAFixedOrder() {
        // The restore error first: no display may be on. The order does not depend on which error came first.
        var first = ErrorSlots()
        first[.restore] = restoreError
        first[.action] = actionError
        var second = ErrorSlots()
        second[.action] = actionError
        second[.restore] = restoreError
        XCTAssertEqual(first.text, "\(restoreError) \(actionError)")
        XCTAssertEqual(second.text, first.text)
    }

    func testTheSameTextFromTwoSourcesIsTwoErrors() {
        // Clearing one source must not clear the other, even with the same text.
        var errors = ErrorSlots()
        errors[.restore] = restoreError
        errors[.action] = restoreError
        errors[.restore] = nil
        XCTAssertEqual(errors.text, restoreError)
    }

    func testRemoveAllClearsEverySource() {
        // The user closed the menu: they have seen every error.
        var errors = ErrorSlots()
        errors[.restore] = restoreError
        errors[.action] = actionError
        errors.removeAll()
        XCTAssertNil(errors.text)
        XCTAssertNil(errors[.restore])
        XCTAssertNil(errors[.action])
    }
}

/// The error of keeping a display on, after the check again of an attempt to turn a display on.
final class RestoreErrorTests: XCTestCase {
    let earlier = "Could not turn on Built-in Retina Display (error 1001)."

    func error(current: String?, restored: UInt32? = nil, failures: [(id: UInt32, error: String)] = [],
               shown: String? = nil) -> String? {
        DisplayPolicy.restoreError(current: current, restored: restored, failures: failures, shown: shown)
    }

    func testADisplayThatTurnedOnClearsIt() {
        XCTAssertNil(error(current: earlier, restored: 1, failures: [(2, "Could not turn on Display 2")]))
    }

    func testNothingToTurnOnClearsIt() {
        // The check again found nothing to turn on: a physical display is on again, for example the display came back
        // by itself during the wait, or another one was plugged in.
        XCTAssertNil(error(current: earlier))
    }

    func testANewErrorReplacesIt() {
        let new = "Could not turn on Built-in Retina Display (error 1000)."
        XCTAssertEqual(error(current: earlier, failures: [(1, new)], shown: new), new)
        XCTAssertEqual(error(current: nil, failures: [(1, new)], shown: new), new)
    }

    func testAFailureThatShowsNoErrorKeepsIt() {
        // A display that may be unplugged failed: its failure shows no error, and no display is on yet.
        XCTAssertEqual(error(current: earlier, failures: [(2, "Could not turn on Display 2")]), earlier)
        XCTAssertNil(error(current: nil, failures: [(2, "Could not turn on Display 2")]))
    }
}

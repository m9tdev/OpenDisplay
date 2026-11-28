import DisplayPolicy
import XCTest

final class UpdateReminderTests: XCTestCase {
    func testNoReminderAtFirst() {
        let reminder = UpdateReminder()
        XCTAssertNil(reminder.menuTitle)
        XCTAssertFalse(reminder.showsBadge)
    }

    func testSparkleShowsAScheduledUpdateOnlyInFocus() {
        XCTAssertTrue(UpdateReminder.sparkleShowsScheduledUpdate(immediateFocus: true))
        // Out of focus, the window would open behind the active app: the menu reminds instead.
        XCTAssertFalse(UpdateReminder.sparkleShowsScheduledUpdate(immediateFocus: false))
    }

    func testAnUpdateThatSparkleDoesNotShowGetsAReminder() {
        var reminder = UpdateReminder()
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: false)
        XCTAssertEqual(reminder.menuTitle, "Update Available: 0.2.3…")
        XCTAssertTrue(reminder.showsBadge)
    }

    func testAnUpdateThatSparkleShowsGetsNoReminder() {
        var reminder = UpdateReminder()
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: true)
        XCTAssertNil(reminder.menuTitle)
        XCTAssertFalse(reminder.showsBadge)
    }

    func testAWindowThatSparkleShowsLaterReplacesTheReminder() {
        // The user checks for updates while a reminder shows: Sparkle shows the window, so the reminder goes.
        var reminder = UpdateReminder()
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: false)
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: true)
        XCTAssertNil(reminder.menuTitle)
    }

    func testANewerUpdateReplacesTheVersion() {
        var reminder = UpdateReminder()
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: false)
        reminder.willShowUpdate(version: "0.2.4", shownBySparkle: false)
        XCTAssertEqual(reminder.menuTitle, "Update Available: 0.2.4…")
    }

    func testTheReminderGoesWhenTheUserAttends() {
        var reminder = UpdateReminder()
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: false)
        reminder.userAttended()
        XCTAssertNil(reminder.menuTitle)
        XCTAssertFalse(reminder.showsBadge)
    }

    func testTheReminderGoesWhenTheSessionEnds() {
        var reminder = UpdateReminder()
        reminder.willShowUpdate(version: "0.2.3", shownBySparkle: false)
        reminder.sessionEnded()
        XCTAssertNil(reminder.menuTitle)
        XCTAssertFalse(reminder.showsBadge)
    }
}

import DisplayPolicy
import Foundation
import XCTest

final class WindowNotificationTests: XCTestCase {
    let settings = NSObject()
    let other = NSObject()

    func testANotificationAboutTheSettingsWindowCounts() {
        XCTAssertTrue(WindowNotification.isAbout(settings, window: settings))
    }

    func testANotificationAboutAnotherWindowDoesNotCount() {
        // For example the calibration window, or a window of another app's panel, becoming key.
        XCTAssertFalse(WindowNotification.isAbout(other, window: settings))
    }

    func testNothingCountsBeforeTheSettingsWindowExists() {
        XCTAssertFalse(WindowNotification.isAbout(other, window: nil))
        // A notification without a window is not about a window that does not exist yet either.
        XCTAssertFalse(WindowNotification.isAbout(nil, window: nil))
    }

    func testANotificationWithoutAWindowDoesNotCount() {
        XCTAssertFalse(WindowNotification.isAbout(nil, window: settings))
    }
}

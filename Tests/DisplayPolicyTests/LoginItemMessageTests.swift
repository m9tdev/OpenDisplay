import DisplayPolicy
import XCTest

final class LoginItemMessageTests: XCTestCase {
    func testAFailureShowsTheError() {
        var message = LoginItemMessage()
        message.failed(wanted: true, message: "Launch at Login: Operation not permitted")
        XCTAssertEqual(message.text, "Launch at Login: Operation not permitted")
    }

    func testASuccessfulToggleClearsTheError() {
        var message = LoginItemMessage()
        message.failed(wanted: true, message: "Launch at Login: Operation not permitted")
        message.succeeded()
        XCTAssertNil(message.text)
    }

    func testTheErrorStaysWhileTheLoginItemIsNotAsWanted() {
        var message = LoginItemMessage()
        message.failed(wanted: true, message: "Launch at Login: Operation not permitted")
        message.checked(isEnabled: false)
        XCTAssertEqual(message.text, "Launch at Login: Operation not permitted")

        message.failed(wanted: false, message: "Launch at Login: Operation not permitted")
        message.checked(isEnabled: true)
        XCTAssertEqual(message.text, "Launch at Login: Operation not permitted")
    }

    func testTheErrorGoesWhenTheUserTurnsTheLoginItemOnInSystemSettings() {
        var message = LoginItemMessage()
        message.failed(wanted: true, message: "Launch at Login: Operation not permitted")
        message.checked(isEnabled: true)
        XCTAssertNil(message.text)
    }

    func testTheErrorGoesWhenTheUserTurnsTheLoginItemOffInSystemSettings() {
        var message = LoginItemMessage()
        message.failed(wanted: false, message: "Launch at Login: Operation not permitted")
        message.checked(isEnabled: false)
        XCTAssertNil(message.text)
    }

    func testAnErrorThatWentDoesNotComeBack() {
        var message = LoginItemMessage()
        message.failed(wanted: true, message: "Launch at Login: Operation not permitted")
        message.checked(isEnabled: true)
        // The user turns it off again in System Settings: no failure, so no error.
        message.checked(isEnabled: false)
        XCTAssertNil(message.text)
    }

    func testANewFailureAfterAFixShows() {
        var message = LoginItemMessage()
        message.failed(wanted: true, message: "Launch at Login: Operation not permitted")
        message.checked(isEnabled: true)
        message.failed(wanted: false, message: "Launch at Login: Invalid argument")
        XCTAssertEqual(message.text, "Launch at Login: Invalid argument")
    }
}

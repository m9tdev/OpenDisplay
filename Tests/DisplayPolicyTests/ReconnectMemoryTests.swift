import DisplayPolicy
import XCTest

/// A monitor that goes away (power button, unplugged, other input) and comes back.
final class ReconnectMemoryTests: XCTestCase {
    let monitor = "4C2D-0E36-1234"

    // MARK: Software dimming

    func testADimmedMonitorGetsItsDimmingBack() {
        var memory = ReconnectMemory()
        memory.displayLeft(key: monitor, dimming: 0.4)
        XCTAssertEqual(memory.displayReturned(key: monitor), 0.4)
    }

    func testAMonitorThatWasNotDimmedComesBackNormal() {
        var memory = ReconnectMemory()
        memory.displayLeft(key: monitor, dimming: 1)
        XCTAssertEqual(memory.displayReturned(key: monitor), 1)
    }

    func testAnotherMonitorDoesNotGetTheDimming() {
        var memory = ReconnectMemory()
        memory.displayLeft(key: monitor, dimming: 0.4)
        XCTAssertEqual(memory.displayReturned(key: "4C2D-0E36-5678"), 1)
        XCTAssertEqual(memory.displayReturned(key: monitor), 0.4)
    }

    func testTheLastDimmingCounts() {
        // It went away dimmed, came back, was set to normal, and went away again.
        var memory = ReconnectMemory()
        memory.displayLeft(key: monitor, dimming: 0.4)
        XCTAssertEqual(memory.displayReturned(key: monitor), 0.4)
        memory.displayLeft(key: monitor, dimming: 1)
        XCTAssertEqual(memory.displayReturned(key: monitor), 1)
    }

    func testTheDimmingIsGivenBackOnce() {
        // Once back, the display object holds the dimming. A later new object (a display with the same key that
        // never left) starts normal.
        var memory = ReconnectMemory()
        memory.displayLeft(key: monitor, dimming: 0.4)
        XCTAssertEqual(memory.displayReturned(key: monitor), 0.4)
        XCTAssertEqual(memory.displayReturned(key: monitor), 1)
    }

    func testADisplayWithoutAKeyIsNotRemembered() {
        // A display that was never on while the app ran: macOS gave no identity for it.
        var memory = ReconnectMemory()
        memory.displayLeft(key: nil, dimming: 0.4)
        XCTAssertEqual(memory, ReconnectMemory())
    }

    // MARK: Brightness sync

    typealias Refreshed = ReconnectMemory.RefreshedDisplay

    func testASyncedMonitorThatComesBackIsSyncedAgain() {
        // The built-in display did not change while the monitor was away, so only this brings the shared brightness
        // back to the monitor.
        XCTAssertTrue(ReconnectMemory.resyncsBrightness([
            Refreshed(wasEnabled: true, isEnabled: true, isSynced: false),
            Refreshed(wasEnabled: nil, isEnabled: true, isSynced: true),
        ]))
    }

    func testASyncedMonitorTurnedOnAgainIsSyncedAgain() {
        // OpenDisplay turned it off and on: the same display object, off before the refresh.
        XCTAssertTrue(ReconnectMemory.resyncsBrightness([Refreshed(wasEnabled: false, isEnabled: true, isSynced: true)]))
    }

    func testNoResyncWhenSyncedMonitorsStayedOn() {
        XCTAssertFalse(ReconnectMemory.resyncsBrightness([
            Refreshed(wasEnabled: true, isEnabled: true, isSynced: true),
            Refreshed(wasEnabled: nil, isEnabled: true, isSynced: false),
        ]))
    }

    func testNoResyncForASyncedMonitorThatIsOff() {
        XCTAssertFalse(ReconnectMemory.resyncsBrightness([
            Refreshed(wasEnabled: true, isEnabled: false, isSynced: true),
            Refreshed(wasEnabled: nil, isEnabled: false, isSynced: true),
        ]))
    }
}

import DisplayPolicy
import XCTest

/// A monitor that goes away (power button, unplugged, other input) and comes back, or that the app turns off and on.
final class ReconnectMemoryTests: XCTestCase {
    typealias Snapshot = ReconnectMemory.Snapshot

    let monitor = "4C2D-0E36-1234"
    let builtin = Snapshot(id: 1, key: "610-A04F-0", isEnabled: true)

    /// The monitor, with ID 2, went away with `dimming`; it comes back with ID `returningID` (macOS may give it a new
    /// ID). Returns the dimming it gets back.
    func reconnect(dimming: Double, returningID: UInt32 = 2, key: String? = nil,
                   memory: inout ReconnectMemory) -> Double? {
        let leaving = Snapshot(id: 2, key: monitor, isEnabled: true, dimming: dimming)
        _ = memory.refresh(before: [builtin, leaving], after: [builtin], turnedOnByApp: [])
        let returning = Snapshot(id: returningID, key: key ?? monitor, isEnabled: true)
        return memory.refresh(before: [builtin], after: [builtin, returning], turnedOnByApp: []).dimming[returningID]
    }

    // MARK: Software dimming

    func testADimmedMonitorGetsItsDimmingBack() {
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 0.4, memory: &memory), 0.4)
    }

    func testADimmedMonitorGetsItsDimmingBackWithANewID() {
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 0.4, returningID: 7, memory: &memory), 0.4)
    }

    func testAMonitorThatWasNotDimmedComesBackNormal() {
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 1, memory: &memory), 1)
    }

    func testAnotherMonitorDoesNotGetTheDimming() {
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 0.4, key: "4C2D-0E36-5678", memory: &memory), 1)
    }

    func testTheLastDimmingCounts() {
        // It went away dimmed, came back, was set to normal, and went away again.
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 0.4, memory: &memory), 0.4)
        XCTAssertEqual(reconnect(dimming: 1, memory: &memory), 1)
    }

    func testTheDimmingIsGivenBackOnce() {
        // Once back, the display object holds the dimming. A later new object with the same key starts normal.
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 0.4, memory: &memory), 0.4)
        let again = Snapshot(id: 3, key: monitor, isEnabled: true)
        XCTAssertEqual(memory.refresh(before: [builtin], after: [builtin, again], turnedOnByApp: []).dimming[3], 1)
    }

    func testADisplayWithoutAKeyIsNotRemembered() {
        // A display that was never on while the app ran: macOS gave no identity for it.
        var memory = ReconnectMemory()
        let leaving = Snapshot(id: 2, key: nil, isEnabled: false, dimming: 0.4)
        _ = memory.refresh(before: [builtin, leaving], after: [builtin], turnedOnByApp: [])
        XCTAssertEqual(memory, ReconnectMemory())
    }

    func testADisplayThatStaysOnKeepsItsDimming() {
        var memory = ReconnectMemory()
        let display = Snapshot(id: 2, key: monitor, isEnabled: true, dimming: 0.4)
        XCTAssertEqual(memory.refresh(before: [builtin, display], after: [builtin, display], turnedOnByApp: []),
                       ReconnectMemory.Plan())
    }

    func testAMonitorDimmedToBlackDoesNotComeBackBlack() {
        // Dimmed to (almost) nothing, it would look dead after a reconnect.
        var memory = ReconnectMemory()
        XCTAssertEqual(reconnect(dimming: 0, memory: &memory), ReconnectMemory.minimumRestoredDimming)
        XCTAssertEqual(reconnect(dimming: 0.01, memory: &memory), ReconnectMemory.minimumRestoredDimming)
        XCTAssertEqual(reconnect(dimming: 0.2, memory: &memory), 0.2)
    }

    func testAMonitorTheAppTurnsOnAgainDoesNotComeBackBlack() {
        // The same display object, so it keeps its dimming; only too dark a dimming changes.
        var memory = ReconnectMemory()
        let off = Snapshot(id: 2, key: monitor, isEnabled: false, dimming: 0)
        let on = Snapshot(id: 2, key: monitor, isEnabled: true, dimming: 0)
        XCTAssertEqual(memory.refresh(before: [builtin, off], after: [builtin, on], turnedOnByApp: []).dimming[2],
                       ReconnectMemory.minimumRestoredDimming)
    }

    // MARK: Brightness sync

    func testASyncedMonitorThatComesBackIsSyncedAgain() {
        // The built-in display did not change while the monitor was away, so only this brings the shared brightness
        // back to the monitor.
        var memory = ReconnectMemory()
        let returning = Snapshot(id: 2, key: monitor, isEnabled: true, isSynced: true)
        XCTAssertTrue(memory.refresh(before: [builtin], after: [builtin, returning], turnedOnByApp: []).resyncsBrightness)
    }

    func testASyncedMonitorSeenOffThenOnIsSyncedAgain() {
        // A refresh saw it off (the app turned it off), and the next one sees it on.
        var memory = ReconnectMemory()
        let off = Snapshot(id: 2, key: monitor, isEnabled: false, isSynced: true)
        let on = Snapshot(id: 2, key: monitor, isEnabled: true, isSynced: true)
        XCTAssertTrue(memory.refresh(before: [builtin, off], after: [builtin, on], turnedOnByApp: []).resyncsBrightness)
    }

    func testASyncedMonitorTheAppTurnedOnIsSyncedAgain() {
        // The app shows the new state at once, so the display is already on in the list before the refresh that
        // follows the turn-on.
        var memory = ReconnectMemory()
        let on = Snapshot(id: 2, key: monitor, isEnabled: true, isSynced: true)
        XCTAssertTrue(memory.refresh(before: [builtin, on], after: [builtin, on], turnedOnByApp: [2]).resyncsBrightness)
    }

    func testNoResyncWhenSyncedMonitorsStayedOn() {
        var memory = ReconnectMemory()
        let synced = Snapshot(id: 2, key: monitor, isEnabled: true, isSynced: true)
        let other = Snapshot(id: 3, key: "4C2D-0E36-5678", isEnabled: true)
        XCTAssertFalse(memory.refresh(before: [builtin, synced], after: [builtin, synced, other],
                                      turnedOnByApp: [3]).resyncsBrightness)
    }

    func testNoResyncForASyncedMonitorThatIsOff() {
        var memory = ReconnectMemory()
        let wasOn = Snapshot(id: 2, key: monitor, isEnabled: true, isSynced: true)
        let nowOff = Snapshot(id: 2, key: monitor, isEnabled: false, isSynced: true)
        let newOff = Snapshot(id: 3, key: nil, isEnabled: false, isSynced: true)
        XCTAssertFalse(memory.refresh(before: [builtin, wasOn], after: [builtin, nowOff, newOff],
                                      turnedOnByApp: [2]).resyncsBrightness)
    }
}

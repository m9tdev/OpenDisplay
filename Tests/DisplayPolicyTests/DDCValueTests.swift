import DisplayPolicy
import XCTest

/// The app's brightness, volume and mute follow the monitor, but a read never undoes a newer value the app set, and
/// writes use the monitor's own maximum.
final class DDCValueTests: XCTestCase {
    /// True if the answer would replace the value the app shows.
    func shows(_ answer: DDCValue.Answer) -> Bool {
        if case .show = answer { return true }
        return false
    }

    // MARK: A read and a newer write

    func testAReadSentBeforeAWriteDoesNotUndoIt() {
        // At launch: the brightness read goes out, then brightness sync sets the monitor before the answer comes back.
        var value = DDCValue()
        let read = value.startRead()
        _ = value.set(0.8)
        // The monitor answers with its level from before the write.
        let (answer, _) = value.finish(read, current: 30, maximum: 100)
        XCTAssertFalse(shows(answer))
        XCTAssertNotEqual(answer, .failed)
    }

    func testAMuteReadSentBeforeAMuteChangeDoesNotUndoIt() {
        var mute = DDCValue()
        let read = mute.startRead()
        mute.setRaw()
        XCTAssertFalse(shows(mute.finish(read, current: 2, maximum: 2).answer))
    }

    func testAReadSentAfterAWriteIsShown() {
        var value = DDCValue()
        _ = value.set(0.8)
        let read = value.startRead()
        XCTAssertEqual(value.finish(read, current: 80, maximum: 100).answer, .show(current: 80, level: 0.8))
    }

    func testAReadWithoutWritesIsShown() {
        var value = DDCValue()
        let read = value.startRead()
        XCTAssertEqual(value.finish(read, current: 30, maximum: 60).answer, .show(current: 30, level: 0.5))
    }

    func testAReadWithoutAnAnswerFails() {
        var value = DDCValue()
        let read = value.startRead()
        XCTAssertEqual(value.finish(read, current: nil, maximum: nil).answer, .failed)
    }

    // MARK: The monitor's maximum

    func testAWriteDuringTheFirstReadUsesTheMonitorsMaximum() {
        // A monitor with a maximum of 50: half is 25, not 50.
        var value = DDCValue()
        let read = value.startRead()
        let now = value.set(0.5)
        let later = value.finish(read, current: 10, maximum: 50).write
        XCTAssertEqual([now, later].compactMap { $0 }, [25])
    }

    func testAWriteDuringAFailedReadStillGoesOut() {
        // Many monitors take writes but do not answer reads.
        var value = DDCValue()
        let read = value.startRead()
        let now = value.set(0.5)
        let later = value.finish(read, current: nil, maximum: nil).write
        XCTAssertEqual([now, later].compactMap { $0 }, [50])
    }

    func testOnlyTheNewestWriteDuringTheFirstReadGoesOut() {
        var value = DDCValue()
        let read = value.startRead()
        _ = value.set(0.2)
        let second = value.set(0.5)
        let later = value.finish(read, current: 10, maximum: 50).write
        XCTAssertEqual([second, later].compactMap { $0 }, [25])
    }

    func testAWriteWithoutAReadAssumesTheUsualMaximum() {
        var value = DDCValue()
        XCTAssertEqual(value.set(0.5), 50)
    }

    func testWritesAfterAReadUseTheMonitorsMaximum() {
        var value = DDCValue()
        let read = value.startRead()
        _ = value.finish(read, current: 10, maximum: 50)
        XCTAssertEqual(value.set(0.5), 25)
        XCTAssertEqual(value.maximum, 50)
    }
}

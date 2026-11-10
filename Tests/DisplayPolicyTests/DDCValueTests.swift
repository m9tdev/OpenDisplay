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

    func testAFailedReadSentBeforeAWriteStillReportsTheFailure() {
        // A monitor that never answers reads still shows that it does not, also when brightness sync set it first.
        var value = DDCValue()
        let read = value.startRead()
        _ = value.set(0.8)
        XCTAssertEqual(value.finish(read, current: nil, maximum: nil).answer, .outdated(failed: true))
    }

    func testAnAnsweredReadSentBeforeAWriteIsNotAFailure() {
        var value = DDCValue()
        let read = value.startRead()
        _ = value.set(0.8)
        XCTAssertEqual(value.finish(read, current: 30, maximum: 100).answer, .outdated(failed: false))
    }

    func testAHeldBackWriteOutdatesAReadSentBeforeItGoesOut() {
        // The write waits for the first read; a second read goes out meanwhile, before the write.
        var value = DDCValue()
        let first = value.startRead()
        XCTAssertNil(value.set(0.5))
        let second = value.startRead()
        XCTAssertEqual(value.finish(first, current: 10, maximum: 50).write, 25)
        XCTAssertFalse(shows(value.finish(second, current: 10, maximum: 50).answer))
    }

    func testAReadSentAfterAHeldBackWriteWentOutIsShown() {
        var value = DDCValue()
        let first = value.startRead()
        _ = value.set(0.5)
        _ = value.finish(first, current: 10, maximum: 50)
        let second = value.startRead()
        XCTAssertEqual(value.finish(second, current: 25, maximum: 50).answer, .show(current: 25, level: 0.5))
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

    // MARK: Writes the app does not show (the calibration's)

    func testACalibrationWriteDuringTheFirstReadUsesTheMonitorsMaximum() {
        var value = DDCValue()
        let read = value.startRead()
        let now = value.set(0.5, outdatesReads: false)
        let later = value.finish(read, current: 10, maximum: 50).write
        XCTAssertEqual([now, later].compactMap { $0 }, [25])
    }

    func testACalibrationWriteLeavesTheReadInFlightShown() {
        // The read answers with the level from before the calibration, which the calibration puts back when it ends.
        var value = DDCValue()
        let read = value.startRead()
        _ = value.set(0.5, outdatesReads: false)
        XCTAssertEqual(value.finish(read, current: 10, maximum: 50).answer, .show(current: 10, level: 0.2))
    }

    func testACalibrationWriteAfterTheAppsWriteKeepsTheReadOutdated() {
        var value = DDCValue()
        let read = value.startRead()
        _ = value.set(0.8)
        _ = value.set(0.5, outdatesReads: false)
        let (answer, write) = value.finish(read, current: 10, maximum: 50)
        XCTAssertEqual(answer, .outdated(failed: false))
        XCTAssertEqual(write, 25)
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

/// A new DDC connection to the same monitor (after a wake).
final class DDCValueNewConnectionTests: XCTestCase {
    func testANewConnectionKeepsTheMaximum() {
        var value = DDCValue()
        let read = value.startRead()
        _ = value.finish(read, current: 30, maximum: 50)
        XCTAssertEqual(value.droppingReads().maximum, 50)
    }

    /// The answer to the read in flight is dropped, so a write must not wait for it.
    func testAWriteDoesNotWaitForAReadOverTheOldConnection() {
        var value = DDCValue()
        let read = value.startRead()
        _ = value.finish(read, current: 30, maximum: 50)
        _ = value.startRead()
        var renewed = value.droppingReads()
        XCTAssertEqual(renewed.set(0.5), 25)
    }

    func testAWriteBeforeAnyAnswerUsesTheUsualMaximum() {
        var value = DDCValue()
        _ = value.startRead()
        var renewed = value.droppingReads()
        XCTAssertEqual(renewed.set(0.5), 50)
    }

    /// After a wake, a monitor that takes writes but does not answer reads keeps the brightness the slider shows.
    func testAFailedReadThatKeepsTheShownValueIsUnanswered() {
        var value = DDCValue().droppingReads()
        let read = value.startRead(keepsShownOnFailure: true)
        XCTAssertEqual(value.finish(read, current: nil, maximum: nil).answer, .unanswered)
    }

    /// Also when the app wrote meanwhile (brightness sync after the wake).
    func testAnOutdatedFailedReadThatKeepsTheShownValueIsUnanswered() {
        var value = DDCValue().droppingReads()
        let read = value.startRead(keepsShownOnFailure: true)
        _ = value.set(0.5)
        XCTAssertEqual(value.finish(read, current: nil, maximum: nil).answer, .unanswered)
    }

    func testAnAnsweredReadThatKeepsTheShownValueIsShown() {
        var value = DDCValue().droppingReads()
        let read = value.startRead(keepsShownOnFailure: true)
        XCTAssertEqual(value.finish(read, current: 40, maximum: 100).answer, .show(current: 40, level: 0.4))
    }

    /// A display that turns on shows nothing yet: a failed read still shows the failure.
    func testAnyOtherFailedReadFails() {
        var value = DDCValue()
        let read = value.startRead()
        XCTAssertEqual(value.finish(read, current: nil, maximum: nil).answer, .failed)
    }

    func testAReadOverTheNewConnectionIsShown() {
        var value = DDCValue()
        _ = value.startRead()
        _ = value.set(0.8)
        var renewed = value.droppingReads()
        let read = renewed.startRead()
        XCTAssertEqual(renewed.finish(read, current: 40, maximum: 100).answer, .show(current: 40, level: 0.4))
    }
}

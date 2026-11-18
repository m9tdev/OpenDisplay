import DisplayPolicy
import XCTest

/// Writes to a display that fail in a row: after a few, the menu shows an error under the display, and the next write
/// that works clears it.
final class WriteFailuresTests: XCTestCase {
    func record(_ failures: inout WriteFailures, _ results: [Bool]) -> [Bool] {
        results.map { failures.record(succeeded: $0) }
    }

    // MARK: DDC

    func testOneFailedDDCWriteShowsNoError() {
        // A monitor that drops one write, for example while it wakes, is not "not responding".
        var failures = WriteFailures.ddc
        failures.record(succeeded: false)
        XCTAssertNil(failures.error)
    }

    func testDDCWritesThatFailInARowShowNotResponding() {
        var failures = WriteFailures.ddc
        let changes = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold))
        XCTAssertEqual(failures.error, WriteFailures.ddcMessage)
        // The error changes only at the last failure: log it once, not at each write.
        XCTAssertEqual(changes, Array(repeating: false, count: WriteFailures.ddcThreshold - 1) + [true])
    }

    func testTheThresholdIsSmall() {
        XCTAssertGreaterThan(WriteFailures.ddcThreshold, 1)
        XCTAssertLessThanOrEqual(WriteFailures.ddcThreshold, 5)
    }

    func testMoreFailuresKeepTheErrorWithoutAChange() {
        var failures = WriteFailures.ddc
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold))
        XCTAssertFalse(failures.record(succeeded: false))
        XCTAssertEqual(failures.error, WriteFailures.ddcMessage)
    }

    func testAWriteThatWorksClearsTheError() {
        var failures = WriteFailures.ddc
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold))
        XCTAssertTrue(failures.record(succeeded: true))
        XCTAssertNil(failures.error)
    }

    func testAWriteThatWorksStartsTheCountAgain() {
        // Failures with a working write between them are not in a row.
        var failures = WriteFailures.ddc
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold - 1))
        failures.record(succeeded: true)
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold - 1))
        XCTAssertNil(failures.error)
    }

    func testWritesThatWorkChangeNothing() {
        var failures = WriteFailures.ddc
        XCTAssertEqual(record(&failures, [true, true]), [false, false])
        XCTAssertNil(failures.error)
    }

    func testAReadThatWorksClearsTheError() {
        // The monitor answered over the same connection: the transport works.
        var failures = WriteFailures.ddc
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold))
        XCTAssertTrue(failures.recordRead(succeeded: true))
        XCTAssertNil(failures.error)
        // And the count starts again.
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold - 1))
        XCTAssertNil(failures.error)
    }

    func testAFailedReadCountsNothing() {
        // Reads also fail when the monitor is slow to answer, so only a read that works counts.
        var failures = WriteFailures.ddc
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold - 1))
        XCTAssertFalse(failures.recordRead(succeeded: false))
        XCTAssertNil(failures.error)
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold))
        XCTAssertFalse(failures.recordRead(succeeded: false))
        XCTAssertEqual(failures.error, WriteFailures.ddcMessage)
    }

    func testAWakeClearsTheErrorAndTheCount() {
        // Writes to a monitor that slept can fail; after the wake, it starts again with no error.
        var failures = WriteFailures.ddc
        _ = record(&failures, Array(repeating: false, count: WriteFailures.ddcThreshold))
        XCTAssertTrue(failures.reset())
        XCTAssertNil(failures.error)
        failures.record(succeeded: false)
        XCTAssertNil(failures.error)
    }

    func testAWakeWithoutAnErrorChangesNothing() {
        var failures = WriteFailures.ddc
        failures.record(succeeded: false)
        XCTAssertFalse(failures.reset())
        XCTAssertNil(failures.error)
    }

    // MARK: Built-in display

    func testOneFailedBuiltinBrightnessWriteShowsAnError() {
        // macOS refused the level: the slider shows a brightness the display does not have.
        var failures = WriteFailures.builtin
        XCTAssertTrue(failures.record(succeeded: false))
        XCTAssertEqual(failures.error, WriteFailures.builtinMessage)
        XCTAssertTrue(failures.record(succeeded: true))
        XCTAssertNil(failures.error)
    }
}

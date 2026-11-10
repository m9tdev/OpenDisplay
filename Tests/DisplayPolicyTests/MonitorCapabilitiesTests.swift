import DisplayPolicy
import XCTest

/// The read of a monitor's VCP codes: once per monitor, never twice at a time, again after a failure.
final class MonitorCapabilitiesTests: XCTestCase {
    let contrast: UInt8 = 0x12
    let input: UInt8 = 0x60
    var listed: [UInt8: [UInt8]] { [contrast: [], input: [0x0F, 0x11]] }

    func reading() -> MonitorCapabilities {
        var capabilities = MonitorCapabilities.unread
        capabilities.startRead()
        return capabilities
    }

    func read(_ codes: [UInt8: [UInt8]]?) -> MonitorCapabilities {
        var capabilities = reading()
        capabilities.finishRead(codes)
        return capabilities
    }

    // MARK: Reads

    func testUnreadCapabilitiesAreRead() {
        XCTAssertTrue(MonitorCapabilities.unread.needsRead)
    }

    /// A refresh during the read does not start a second one.
    func testAReadInFlightIsNotStartedAgain() {
        XCTAssertEqual(reading(), .reading)
        XCTAssertFalse(reading().needsRead)
    }

    func testAnAnswerKeepsTheCodes() {
        XCTAssertEqual(read(listed), .read(listed))
        XCTAssertFalse(read(listed).needsRead)
    }

    /// The next refresh tries again.
    func testAFailedReadIsReadAgain() {
        XCTAssertEqual(read(nil), .unread)
        XCTAssertTrue(read(nil).needsRead)
    }

    /// A monitor whose capabilities string lists no codes answered: it is not read again at each refresh.
    func testAnAnswerWithoutCodesIsNotReadAgain() {
        XCTAssertEqual(read([:]), .read([:]))
        XCTAssertFalse(read([:]).needsRead)
    }

    // MARK: Rows

    /// The menu shows a row only for a listed code.
    func testCodesAreEmptyUntilRead() {
        XCTAssertEqual(MonitorCapabilities.unread.codes, [:])
        XCTAssertEqual(reading().codes, [:])
        XCTAssertEqual(read(nil).codes, [:])
        XCTAssertEqual(read(listed).codes, listed)
    }

    // MARK: Monitor settings

    func testWithoutAListEveryCodeMayBeSupported() {
        XCTAssertTrue(MonitorCapabilities.unread.maySupport(contrast))
        XCTAssertTrue(reading().maySupport(contrast))
        XCTAssertTrue(read([:]).maySupport(contrast))
    }

    func testAListTellsTheSupportedCodes() {
        XCTAssertTrue(read(listed).maySupport(contrast))
        XCTAssertFalse(read(listed).maySupport(0x14))
    }

    // MARK: New connection

    /// The answer over the old connection is dropped, so the read starts again.
    func testANewConnectionDropsTheReadInFlight() {
        var capabilities = reading()
        capabilities.connectionChanged()
        XCTAssertEqual(capabilities, .unread)
        XCTAssertTrue(capabilities.needsRead)
    }

    /// The codes belong to the monitor, not to the connection.
    func testANewConnectionKeepsListedCodes() {
        var capabilities = read(listed)
        capabilities.connectionChanged()
        XCTAssertEqual(capabilities, .read(listed))
    }

    func testANewConnectionReadsAnEmptyListAgain() {
        var capabilities = read([:])
        capabilities.connectionChanged()
        XCTAssertEqual(capabilities, .unread)
    }

    func testANewConnectionLeavesUnreadCapabilitiesUnread() {
        var capabilities = MonitorCapabilities.unread
        capabilities.connectionChanged()
        XCTAssertEqual(capabilities, .unread)
    }
}

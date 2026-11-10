import DisplayPolicy
import XCTest

/// A display that keeps its display ID across a refresh, while the monitor behind it or its DDC connection may change.
final class MonitorLinkTests: XCTestCase {
    let monitor = "4C2D-0E36-1234"
    let other = "4C2D-0E36-5678"

    /// A connection whose registry entry ID could not be read.
    static let unreadEntry: UInt64 = .max

    /// `nil`: no DDC; `unreadEntry`: DDC, without an entry ID.
    func link(_ key: String?, _ entry: UInt64?) -> MonitorLink {
        MonitorLink(key: key, connection: entry.map { MonitorLink.Connection(entry: $0 == Self.unreadEntry ? nil : $0) })
    }

    func change(_ oldKey: String?, _ oldConnection: UInt64?, to newKey: String?, _ newConnection: UInt64?) -> MonitorLink.Change {
        MonitorLink.change(from: link(oldKey, oldConnection), to: link(newKey, newConnection))
    }

    // MARK: Change

    func testTheSameMonitorAndConnectionIsTheSame() {
        XCTAssertEqual(change(monitor, 7, to: monitor, 7), .same)
    }

    func testTheSameMonitorWithoutDDCIsTheSame() {
        XCTAssertEqual(change(monitor, nil, to: monitor, nil), .same)
    }

    func testDDCAppearsAndGoes() {
        XCTAssertEqual(change(monitor, nil, to: monitor, 7), .connectionAppeared)
        XCTAssertEqual(change(monitor, 7, to: monitor, nil), .connectionLost)
    }

    /// After a wake, or a fast replug of the same monitor, macOS makes a new DDC service.
    func testANewConnectionToTheSameMonitorReplacesTheConnection() {
        XCTAssertEqual(change(monitor, 7, to: monitor, 9), .connectionReplaced)
    }

    /// Another monitor plugged in within the refresh delay, with the same display ID.
    func testAnotherMonitorWithTheSameIDReplacesTheMonitor() {
        XCTAssertEqual(change(monitor, 7, to: other, 9), .monitorReplaced)
    }

    /// The registry entry may stay (for example a port that keeps its service): the key still tells the monitors apart.
    func testAnotherMonitorOnTheSameConnectionReplacesTheMonitor() {
        XCTAssertEqual(change(monitor, 7, to: other, 7), .monitorReplaced)
    }

    func testAnotherMonitorWithoutDDCReplacesTheMonitor() {
        XCTAssertEqual(change(monitor, nil, to: other, nil), .monitorReplaced)
        XCTAssertEqual(change(monitor, 7, to: other, nil), .monitorReplaced)
        XCTAssertEqual(change(monitor, nil, to: other, 7), .monitorReplaced)
    }

    /// Without a key on one side, only the connections can tell.
    func testAMissingKeyComparesTheConnectionsOnly() {
        XCTAssertEqual(change(nil, 7, to: monitor, 7), .same)
        XCTAssertEqual(change(monitor, 7, to: nil, 7), .same)
        XCTAssertEqual(change(nil, 7, to: monitor, 9), .connectionReplaced)
        XCTAssertEqual(change(nil, nil, to: monitor, 7), .connectionAppeared)
    }

    /// Two connections whose entry IDs could not be read may be different connections.
    func testConnectionsWithoutAnEntryIDAreNeverTheSame() {
        XCTAssertEqual(change(monitor, Self.unreadEntry, to: monitor, Self.unreadEntry), .connectionReplaced)
        XCTAssertEqual(change(monitor, 7, to: monitor, Self.unreadEntry), .connectionReplaced)
        XCTAssertEqual(change(monitor, Self.unreadEntry, to: monitor, 7), .connectionReplaced)
    }

    // MARK: Resets

    func testTheSameLinkKeepsEverything() {
        XCTAssertEqual(MonitorLink.resets(for: .same), [])
    }

    /// As before: the new connection (or none), and the values read again. The monitor keeps its dimming.
    func testDDCAppearingOrGoingReadsTheValuesAgain() {
        for change: MonitorLink.Change in [.connectionAppeared, .connectionLost] {
            XCTAssertEqual(MonitorLink.resets(for: change), [.connection, .readValues], "\(change)")
        }
    }

    /// After a wake the monitor may not accept DDC yet: the slider keeps its value until a later read, and a synced
    /// display gets the shared brightness again, as when it turns on.
    func testANewConnectionReadsWhenTheMonitorIsReadyAndResyncs() {
        let resets = MonitorLink.resets(for: .connectionReplaced)
        XCTAssertEqual(resets, [.connection, .readValuesWhenReady, .resync])
        XCTAssertFalse(resets.contains(.readValues), "the slider keeps its value until the monitor answers")
        XCTAssertFalse(resets.contains(.dimming), "the same monitor keeps its dimming")
        XCTAssertFalse(resets.contains(.monitorState), "the same monitor keeps what the app knows about it")
    }

    func testAnotherMonitorResetsEverything() {
        XCTAssertEqual(MonitorLink.resets(for: .monitorReplaced),
                       [.connection, .readValues, .resync, .monitorState, .dimming])
    }

    /// The display keeps its ID: the old monitor's color table must not be written onto the new one.
    func testAnotherMonitorDropsTheSavedColorTable() {
        XCTAssertTrue(MonitorLink.resets(for: change(monitor, 7, to: other, 7)).contains(.dimming))
    }
}

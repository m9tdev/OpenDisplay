import DisplayPolicy
import XCTest

/// The displays that OpenDisplay turned off ("marks"), with the login session each mark was made in. macOS turns a
/// display off for the login session only, so a mark from an earlier session is stale: the display was unplugged
/// while off, and it would stay "off" in the menu for good.
final class OffMarksTests: XCTestCase {
    // 1 is the built-in display, 3 a TV, and 5 the placeholder display that macOS makes when no display is on.
    let earlier = "session-earlier", now = "session-now"
    let placeholder = DisplayState(id: 5, isVirtual: true)

    /// The safety net's choice for `marks`, with every marked display off and offline (unplugged, or the built-in
    /// display, which macOS reports as offline while it is off), and only the placeholder on.
    func restored(_ marks: OffMarks, builtins: Set<UInt32> = [1]) -> [UInt32] {
        let off = marks.names.keys.sorted().map {
            DisplayState(id: $0, isBuiltin: builtins.contains($0), isOnline: false, isActive: false,
                         isDisabledByUs: true)
        }
        return DisplayPolicy.displaysToRestore(in: off + [placeholder])
    }

    // MARK: Pruning

    func testAnUnpluggedDisplayMarkedInAnEarlierSessionIsNoLongerOff() {
        let marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        let pruned = marks.pruned(session: now, builtins: [1])
        XCTAssertEqual(pruned, OffMarks(names: [:], sessions: [:]))
        XCTAssertEqual(restored(pruned), [])
    }

    func testADisplayMarkedInThisSessionStaysMarkedWhenUnplugged() {
        let marks = OffMarks(names: [3: "TV"], sessions: [3: now])
        XCTAssertEqual(marks.pruned(session: now, builtins: [1]), marks)
    }

    func testTheBuiltinDisplaysMarkFromAnEarlierSessionIsKept() {
        // The safety net turns on only marked displays: without this mark, a MacBook whose external display is
        // unplugged would have no screen.
        let marks = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [1: earlier, 3: earlier])
        let pruned = marks.pruned(session: now, builtins: [1])
        XCTAssertEqual(pruned.names, [1: "Built-in"])
        XCTAssertEqual(restored(pruned), [1])
    }

    func testWithoutAKnownSessionNoMarkIsDroppedOrStamped() {
        let marks = OffMarks(names: [3: "TV", 4: "Projector"], sessions: [3: earlier])
        XCTAssertEqual(marks.pruned(session: nil, builtins: []), marks)
    }

    func testTheSessionOfARemovedMarkIsForgotten() {
        let marks = OffMarks(names: [:], sessions: [3: now])
        XCTAssertEqual(marks.pruned(session: now, builtins: []), OffMarks(names: [:], sessions: [:]))
        XCTAssertEqual(marks.pruned(session: nil, builtins: []), OffMarks(names: [:], sessions: [:]))
    }

    // MARK: Marks saved by earlier versions, without a session

    func testALegacyMarkIsKeptAndStampedWithThisSession() {
        let legacy = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [:])
        let migrated = legacy.pruned(session: now, builtins: [1])
        XCTAssertEqual(migrated, OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [1: now, 3: now]))
        // Kept for the whole session, also at later refreshes.
        XCTAssertEqual(migrated.pruned(session: now, builtins: [1]), migrated)
        // Only a later session drops it, and never the built-in display's.
        XCTAssertEqual(migrated.pruned(session: "session-later", builtins: [1]).names, [1: "Built-in"])
    }

    // MARK: Turning displays off and on

    func testTurningADisplayOffStampsThisSession() {
        var marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        marks.markOff(3, name: "TV", session: now)
        marks.markOff(4, name: "Projector", session: now)
        XCTAssertEqual(marks, OffMarks(names: [3: "TV", 4: "Projector"], sessions: [3: now, 4: now]))
        XCTAssertEqual(marks.pruned(session: now, builtins: []), marks)
    }

    func testADisplayTurnedOffWithoutAKnownSessionIsStampedLater() {
        var marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        marks.markOff(3, name: "TV", session: nil)
        XCTAssertEqual(marks, OffMarks(names: [3: "TV"], sessions: [:]))
        XCTAssertEqual(marks.pruned(session: now, builtins: []), OffMarks(names: [3: "TV"], sessions: [3: now]))
    }

    func testTurningADisplayOnRemovesItsMark() {
        var marks = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [1: now, 3: now])
        marks.markOn(3)
        XCTAssertEqual(marks, OffMarks(names: [1: "Built-in"], sessions: [1: now]))
    }

    // MARK: The safety net

    func testTheSafetyNetFindsADisplayTurnedOffInThisSession() {
        var marks = OffMarks(names: [:], sessions: [:])
        marks.markOff(3, name: "TV", session: now)
        XCTAssertEqual(restored(marks.pruned(session: now, builtins: [1])), [3])
        marks.markOff(1, name: "Built-in", session: now)
        XCTAssertEqual(restored(marks.pruned(session: now, builtins: [1])), [1, 3])
    }

    func testTheSafetyNetFindsADisplayTurnedOffBeforeTheMigration() {
        // Saved by an earlier version: names only. The built-in display is off and the TV was unplugged; macOS
        // answers -1 for the built-in display it does not know now, and shows its placeholder.
        let legacy = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [:])
        let marks = legacy.pruned(session: now, builtins: [1])
        let reports = [
            DisplayReport(id: 13, isBuiltin: 0, isOnline: 1, isActive: 1, vendor: 0x756E_6B6E, model: 0x7669_7274),
            DisplayReport(id: 1, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF, model: 0xFFFF_FFFF),
            DisplayReport(id: 3, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF, model: 0xFFFF_FFFF),
        ]
        let states = DisplayPolicy.states(online: [13], active: [13], reports: reports,
                                          disabled: Set(marks.names.keys), builtins: [1])
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1, 3])
    }

    // MARK: The login session

    func testTheLoginSessionIsTheUniqueSessionOfTheWindowServer() {
        XCTAssertEqual(LoginSession.identifier(uniqueSession: "EC734599-ED17-4A4E-8401-9C1DFDDE73CB",
                                               auditSession: 100_020, bootSession: "C0AA1E1B"),
                       "EC734599-ED17-4A4E-8401-9C1DFDDE73CB")
    }

    func testWithoutTheUniqueSessionTheAuditSessionOfThisBootIsTheLoginSession() {
        // Audit session IDs start again at each boot: alone, they could repeat after a restart.
        XCTAssertEqual(LoginSession.identifier(uniqueSession: nil, auditSession: 100_020, bootSession: "C0AA1E1B"),
                       "C0AA1E1B/100020")
        XCTAssertEqual(LoginSession.identifier(uniqueSession: "", auditSession: 100_020, bootSession: "C0AA1E1B"),
                       "C0AA1E1B/100020")
    }

    func testWithoutEnoughToKnowTheSessionItIsUnknown() {
        XCTAssertNil(LoginSession.identifier(uniqueSession: nil, auditSession: nil, bootSession: "C0AA1E1B"))
        XCTAssertNil(LoginSession.identifier(uniqueSession: nil, auditSession: 100_020, bootSession: nil))
        XCTAssertNil(LoginSession.identifier(uniqueSession: nil, auditSession: 100_020, bootSession: ""))
    }
}

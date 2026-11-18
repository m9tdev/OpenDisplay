import DisplayPolicy
import XCTest

/// The displays that OpenDisplay turned off ("marks"), with the login session each mark was made in. macOS turns a
/// display off for the login session only, so a mark from an earlier session is stale once its display is unplugged:
/// it would stay "off" in the menu for good.
final class OffMarksTests: XCTestCase {
    // 1 is the built-in display, 3 a TV, and 5 the placeholder display that macOS makes when no display is on.
    // Sessions are "boot/login": `earlier` is an earlier login of the same boot (a logout without a restart), and
    // `beforeRestart` a login of an earlier boot.
    let earlier = "boot-a/login-1", now = "boot-a/login-2", beforeRestart = "boot-z/login-1"
    let placeholder = DisplayState(id: 5, isVirtual: true)

    /// What macOS answers for a display: `CGDisplayIsBuiltin` and `CGDisplayIsOnline`. 0 for a display it knows and
    /// that is not connected now, -1 for one it does not know now (a display that is off, or one not seen since the
    /// restart).
    func report(_ id: UInt32, builtin: Int32 = 0, online: Int32) -> DisplayReport {
        DisplayReport(id: id, isBuiltin: builtin, isOnline: online, isActive: online == 1 ? 0 : online,
                      vendor: 0, model: 0)
    }

    func pruned(_ marks: OffMarks, session: String?, builtins: Set<UInt32> = [1], online: [UInt32] = [],
                reports: [DisplayReport] = []) -> OffMarks {
        marks.pruned(session: session, builtins: builtins, online: online, reports: reports)
    }

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
        // After a logout: macOS still knows the TV's ID and answers 0, it is not connected.
        let marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        let kept = pruned(marks, session: now, reports: [report(3, online: 0)])
        XCTAssertEqual(kept, OffMarks(names: [:], sessions: [:]))
        XCTAssertEqual(restored(kept), [])
    }

    func testADisplayMarkedBeforeARestartIsNoLongerOff() {
        // A restart turns every display on again. macOS does not know the ID of the unplugged TV now: -1.
        let marks = OffMarks(names: [3: "TV"], sessions: [3: beforeRestart])
        XCTAssertEqual(pruned(marks, session: now, reports: [report(3, online: -1)]), OffMarks(names: [:], sessions: [:]))
        XCTAssertEqual(pruned(marks, session: now), OffMarks(names: [:], sessions: [:]))
    }

    func testADisplayInTheOnlineListKeepsItsMarkFromBeforeARestart() {
        // The display is connected, so its mark may be the only way back to it, whatever the mark's session says.
        let marks = OffMarks(names: [3: "TV"], sessions: [3: beforeRestart])
        let kept = pruned(marks, session: now, builtins: [], online: [3], reports: [report(3, online: -1)])
        XCTAssertEqual(kept, marks)
        XCTAssertEqual(restored(kept, builtins: []), [3])
        XCTAssertEqual(pruned(marks, session: now, builtins: [], online: [3], reports: [report(3, online: 1)]), marks)
    }

    func testADisplayStillConnectedKeepsItsMarkFromAnEarlierSessionOfThisBoot() {
        // If the TV is still off after the session changed, its mark must stay: it is the only way back to it, for
        // the menu and for the safety net. On a Mac without a built-in display, nothing else could turn it on.
        let marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        // In the online list.
        XCTAssertEqual(pruned(marks, session: now, builtins: [], online: [3], reports: [report(3, online: 1)]), marks)
        // macOS does not know it now (-1), as for a display that is off.
        let unknown = pruned(marks, session: now, builtins: [], reports: [report(3, online: -1)])
        XCTAssertEqual(unknown, marks)
        XCTAssertEqual(restored(unknown, builtins: []), [3])
        // No answer at all.
        XCTAssertEqual(pruned(marks, session: now, builtins: []), marks)
        // In the online list, even if its own answer says otherwise.
        XCTAssertEqual(pruned(marks, session: now, builtins: [], online: [3], reports: [report(3, online: 0)]), marks)
    }

    func testADisplayMarkedInThisSessionStaysMarkedWhenUnplugged() {
        let marks = OffMarks(names: [3: "TV"], sessions: [3: now])
        XCTAssertEqual(pruned(marks, session: now, reports: [report(3, online: 0)]), marks)
    }

    func testTheBuiltinDisplaysMarkFromAnEarlierSessionIsKept() {
        // The safety net turns on only marked displays: without this mark, a MacBook whose external display is
        // unplugged would have no screen.
        let marks = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [1: beforeRestart, 3: beforeRestart])
        let kept = pruned(marks, session: now, reports: [report(1, builtin: -1, online: -1), report(3, online: -1)])
        XCTAssertEqual(kept.names, [1: "Built-in"])
        XCTAssertEqual(restored(kept), [1])
    }

    func testADisplayThatMacOSSaysIsBuiltinKeepsItsMark() {
        // Not remembered as built-in, but macOS answers 1.
        let marks = OffMarks(names: [1: "Built-in"], sessions: [1: beforeRestart])
        XCTAssertEqual(pruned(marks, session: now, builtins: [], reports: [report(1, builtin: 1, online: 0)]), marks)
        XCTAssertEqual(pruned(marks, session: now, builtins: [], reports: [report(1, builtin: 0, online: 0)]).names,
                       [:])
    }

    func testWithoutAKnownSessionNoMarkIsDroppedOrStamped() {
        let marks = OffMarks(names: [3: "TV", 4: "Projector"], sessions: [3: beforeRestart])
        XCTAssertEqual(pruned(marks, session: nil, reports: [report(3, online: 0), report(4, online: 0)]), marks)
    }

    func testTheSessionOfARemovedMarkIsForgotten() {
        let marks = OffMarks(names: [:], sessions: [3: now])
        XCTAssertEqual(pruned(marks, session: now), OffMarks(names: [:], sessions: [:]))
        XCTAssertEqual(pruned(marks, session: nil), OffMarks(names: [:], sessions: [:]))
    }

    // MARK: Marks saved by earlier versions, without a session

    func testALegacyMarkIsKeptAndStampedWithThisSession() {
        let legacy = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [:])
        let gone = [report(1, builtin: -1, online: -1), report(3, online: 0)]
        let migrated = pruned(legacy, session: now, reports: gone)
        XCTAssertEqual(migrated, OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [1: now, 3: now]))
        // Kept for the whole session, also at later refreshes.
        XCTAssertEqual(pruned(migrated, session: now, reports: gone), migrated)
        // Only a later session drops it, and never the built-in display's.
        XCTAssertEqual(pruned(migrated, session: "boot-a/login-3", reports: gone).names, [1: "Built-in"])
    }

    // MARK: Turning displays off and on

    func testTurningADisplayOffStampsThisSession() {
        var marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        marks.markOff(3, name: "TV", session: now)
        marks.markOff(4, name: "Projector", session: now)
        XCTAssertEqual(marks, OffMarks(names: [3: "TV", 4: "Projector"], sessions: [3: now, 4: now]))
        XCTAssertEqual(pruned(marks, session: now, reports: [report(3, online: 0), report(4, online: 0)]), marks)
    }

    func testADisplayTurnedOffWithoutAKnownSessionIsStampedLater() {
        var marks = OffMarks(names: [3: "TV"], sessions: [3: earlier])
        marks.markOff(3, name: "TV", session: nil)
        XCTAssertEqual(marks, OffMarks(names: [3: "TV"], sessions: [:]))
        XCTAssertEqual(pruned(marks, session: now, reports: [report(3, online: 0)]),
                       OffMarks(names: [3: "TV"], sessions: [3: now]))
    }

    func testTurningADisplayOnRemovesItsMark() {
        var marks = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [1: now, 3: now])
        marks.markOn(3)
        XCTAssertEqual(marks, OffMarks(names: [1: "Built-in"], sessions: [1: now]))
    }

    // MARK: The safety net

    func testTheSafetyNetFindsADisplayTurnedOffInThisSession() {
        var marks = OffMarks(names: [:], sessions: [:])
        let gone = [report(1, builtin: -1, online: -1), report(3, online: 0)]
        marks.markOff(3, name: "TV", session: now)
        XCTAssertEqual(restored(pruned(marks, session: now, reports: gone)), [3])
        marks.markOff(1, name: "Built-in", session: now)
        XCTAssertEqual(restored(pruned(marks, session: now, reports: gone)), [1, 3])
    }

    func testTheSafetyNetFindsADisplayTurnedOffBeforeTheMigration() {
        // Saved by an earlier version: names only. The built-in display is off and the TV was unplugged; macOS
        // answers -1 for the built-in display it does not know now, and shows its placeholder.
        let legacy = OffMarks(names: [1: "Built-in", 3: "TV"], sessions: [:])
        let reports = [
            DisplayReport(id: 13, isBuiltin: 0, isOnline: 1, isActive: 1, vendor: 0x756E_6B6E, model: 0x7669_7274),
            DisplayReport(id: 1, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF, model: 0xFFFF_FFFF),
            DisplayReport(id: 3, isBuiltin: 0, isOnline: 0, isActive: 0, vendor: 0x09D1, model: 0x7F2B),
        ]
        let marks = pruned(legacy, session: now, online: [13], reports: reports)
        let states = DisplayPolicy.states(online: [13], active: [13], reports: reports,
                                          disabled: Set(marks.names.keys), builtins: [1])
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1, 3])
    }

    // MARK: The login session

    func testTheLoginSessionIsTheUniqueSessionOfTheWindowServerInThisBoot() {
        XCTAssertEqual(LoginSession.identifier(uniqueSession: "EC734599-ED17-4A4E-8401-9C1DFDDE73CB",
                                               auditSession: 100_020, bootSession: "C0AA1E1B"),
                       "C0AA1E1B/EC734599-ED17-4A4E-8401-9C1DFDDE73CB")
        // Without the boot session, a restart is not recognized as such: only the unplugged rule drops marks.
        XCTAssertEqual(LoginSession.identifier(uniqueSession: "EC734599", auditSession: 100_020, bootSession: nil),
                       "EC734599")
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

    func testAMarkWithoutABootIsDroppedOnlyWhenItsDisplayIsUnplugged() {
        // A session saved without its boot: a restart is not recognized, so -1 keeps the mark.
        let marks = OffMarks(names: [3: "TV"], sessions: [3: "login-1"])
        XCTAssertEqual(pruned(marks, session: now, reports: [report(3, online: -1)]), marks)
        XCTAssertEqual(pruned(marks, session: now, reports: [report(3, online: 0)]).names, [:])
        // The same when this session has no boot.
        let withBoot = OffMarks(names: [3: "TV"], sessions: [3: beforeRestart])
        XCTAssertEqual(pruned(withBoot, session: "login-2", reports: [report(3, online: -1)]), withBoot)
    }
}

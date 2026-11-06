import DisplayPolicy
import Foundation
import XCTest

/// While the brightness calibration runs, it alone sets the brightness, and what it changed comes back however it ends.
final class CalibrationPolicyTests: XCTestCase {
    // MARK: Brightness keys and other brightness changes

    func testBrightnessKeysAreIgnoredWhileCalibrating() {
        XCTAssertEqual(CalibrationPolicy.brightnessKey(isCalibrating: true), .ignore)
    }

    func testBrightnessKeysWorkWithoutCalibration() {
        XCTAssertEqual(CalibrationPolicy.brightnessKey(isCalibrating: false), .normal)
    }

    func testOtherBrightnessChangesWaitForTheCalibration() {
        XCTAssertFalse(CalibrationPolicy.allowsBrightnessChange(isCalibrating: true))
    }

    func testOtherBrightnessChangesWorkWithoutCalibration() {
        XCTAssertTrue(CalibrationPolicy.allowsBrightnessChange(isCalibrating: false))
    }

    func testBuiltinChangedByMacOSIsSetAgain() {
        // One brightness key step up from the calibration's level.
        XCTAssertTrue(CalibrationPolicy.mustSetBuiltinAgain(notified: 0.4 + 1.0 / 16, calibrationLevel: 0.4))
        // One fine step down.
        XCTAssertTrue(CalibrationPolicy.mustSetBuiltinAgain(notified: 0.4 - 1.0 / 64, calibrationLevel: 0.4))
    }

    func testTheCalibrationsOwnLevelIsNotSetAgain() {
        // macOS reports each change, also the calibration's own; setting it again would never end.
        XCTAssertFalse(CalibrationPolicy.mustSetBuiltinAgain(notified: 0.4, calibrationLevel: 0.4))
        XCTAssertFalse(CalibrationPolicy.mustSetBuiltinAgain(notified: 0.4001, calibrationLevel: 0.4))
    }

    func testNothingIsSetAgainBeforeTheCalibrationSetALevel() {
        XCTAssertFalse(CalibrationPolicy.mustSetBuiltinAgain(notified: 0.7, calibrationLevel: nil))
    }

    // MARK: Built-in level set again

    func testAKeyPressIsUndone() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertEqual(watch.reported(0.4, at: 0), nil)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0), 0.4)
    }

    func testTheSameKeyPressedAgainIsUndoneAgain() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0), 0.4)
        XCTAssertEqual(watch.reported(0.4, at: 0), nil)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0), 0.4)
    }

    func testALevelMacOSReportsOtherwiseIsSetAgainOnce() {
        // macOS clamps the lowest step's level, and reports each set with its own value.
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.01)
        XCTAssertEqual(watch.reported(0.03, at: 0), 0.01)
        XCTAssertEqual(watch.reported(0.03, at: 0), nil)
        XCTAssertEqual(watch.reported(0.03, at: 0), nil)
    }

    func testSetsAgainStopWhenReportsNeverSettle() {
        // Two reports for each set, one of them never the level: without a limit, this goes on forever.
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        var sets = 0
        for _ in 0..<1000 {
            if watch.reported(0.5, at: 0) != nil { sets += 1 }
            _ = watch.reported(0.4, at: 0)
        }
        XCTAssertLessThanOrEqual(sets, CalibrationBuiltinWatch.maximumSetsAgain)
    }

    func testANewLevelFromTheCalibrationAllowsSetsAgain() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        for _ in 0..<1000 {
            _ = watch.reported(0.5, at: 0)
            _ = watch.reported(0.4, at: 0)
        }
        watch.calibrationSet(0.6)
        XCTAssertEqual(watch.reported(0.5, at: 0), 0.6)
    }

    func testKeyPressesSpacedOutOnOneLevelAreAllUndone() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        for press in 0..<9 {
            let time = Double(press) * 2
            XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: time), 0.4, "key press \(press + 1)")
            // macOS reports the set again.
            XCTAssertEqual(watch.reported(0.4, at: time + 0.05), nil)
        }
    }

    func testKeyPressesSpacedOutAreAllUndoneWhenMacOSRoundsTheLevel() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.01)
        for press in 0..<9 {
            let time = Double(press) * 2
            XCTAssertEqual(watch.reported(0.01 + 1.0 / 16, at: time), 0.01, "key press \(press + 1)")
            // macOS reports the set again with a rounded value, which is set again once.
            XCTAssertEqual(watch.reported(0.03, at: time + 0.05), 0.01)
            XCTAssertEqual(watch.reported(0.03, at: time + 0.1), nil)
        }
    }

    func testTheSameKeyAgainIsUndoneIfMacOSDidNotReportTheSetAgain() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0), 0.4)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 2), 0.4)
    }

    func testTheSameKeyAgainSoonIsUndoneIfMacOSDidNotReportTheSetAgain() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0), 0.4)
        // No report of the set again; the same key again, half a second later.
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0.5), 0.4)
    }

    /// A held key, or quick presses: 20 reports in a second, each one step further, and no reports of the sets again.
    func holdKey(_ watch: inout CalibrationBuiltinWatch, from start: Float, at time: Double) -> Float {
        var value = start
        for step in 0..<20 {
            value = min(start + Float(step + 1) / 16, 1)
            _ = watch.reported(value, at: time + Double(step) * 0.05)
        }
        return value
    }

    func testAHeldKeyEndsBackOnTheLevel() throws {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        let last = holdKey(&watch, from: 0.4, at: 0)
        XCTAssertEqual(last, 1)
        let check = try XCTUnwrap(watch.settleCheckTime)
        XCTAssertGreaterThan(check, 0.95)
        XCTAssertEqual(watch.settled(last, at: check + 0.1), 0.4)
    }

    func testNoSettleCheckBeforeTheReportsStop() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertNil(watch.settleCheckTime)
        XCTAssertEqual(watch.reported(0.5, at: 0), 0.4)
        XCTAssertEqual(watch.settleCheckTime, CalibrationBuiltinWatch.quietTime)
        // Too early: a report could still come.
        XCTAssertNil(watch.settled(0.5, at: 0.5))
    }

    func testASettleCheckOnTheLevelSetsNothing() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertEqual(watch.reported(0.5, at: 0), 0.4)
        XCTAssertNil(watch.settled(0.4, at: 1.1))
        XCTAssertNil(watch.settleCheckTime)
    }

    func testASettleCheckSetsTheValueMacOSMakesOfTheLevelOnlyOnce() {
        // macOS clamps the level to 0.03: setting it again does not change that.
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.01)
        XCTAssertEqual(watch.reported(0.03, at: 0), 0.01)
        XCTAssertEqual(watch.reported(0.03, at: 0.05), nil)
        XCTAssertEqual(watch.settled(0.03, at: 1.2), 0.01)
        XCTAssertEqual(watch.reported(0.03, at: 1.25), nil)
        XCTAssertNil(watch.settled(0.03, at: 2.4))
    }

    func testASecondPressRightAfterTheFirstEndsBackOnTheLevel() {
        // macOS does not report the set again, so the second press gives the same value right after it.
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        XCTAssertEqual(watch.reported(0.4 + 1.0 / 16, at: 0), 0.4)
        _ = watch.reported(0.4 + 1.0 / 16, at: 0.1)
        XCTAssertEqual(watch.settled(0.4 + 1.0 / 16, at: 1.2), 0.4)
    }

    func testSetsAgainStopWhenMacOSNeverShowsTheLevel() {
        // A key press, then after each set again macOS reports and shows another value away from the level (0.5 and
        // 0.6 in turn), never the level. The app reads the brightness at each settle check that is due.
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        var time = 0.0
        var shown: Float = 0.5
        var report: Float? = 0.5
        var sets = 0
        func setAgain() {
            sets += 1
            shown = shown == 0.5 ? 0.6 : 0.5
            report = shown
            time += 0.05
        }
        for _ in 0..<10_000 {
            if let value = report {
                report = nil
                if watch.reported(value, at: time) != nil { setAgain() }
            } else if let check = watch.settleCheckTime {
                time = check + 0.1
                if watch.settled(shown, at: time) != nil { setAgain() }
            } else {
                break
            }
        }
        XCTAssertNil(report)
        XCTAssertNil(watch.settleCheckTime)
        XCTAssertLessThanOrEqual(sets, 2 * CalibrationBuiltinWatch.maximumSetsAgain)
    }

    func testHeldKeysAgainAndAgainEndBackOnTheLevel() {
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        for hold in 0..<20 {
            let time = Double(hold) * 3
            let last = holdKey(&watch, from: 0.4, at: time)
            XCTAssertEqual(watch.settled(last, at: time + 2.1), 0.4, "hold \(hold + 1)")
            // macOS reports the level.
            XCTAssertNil(watch.reported(0.4, at: time + 2.15))
            XCTAssertNil(watch.settled(0.4, at: time + 2.2))
        }
    }

    func testReportsThatNeverSettleStopAlsoOverTime() {
        // Reports a millisecond apart, for 10 seconds: the limit holds as long as they come quickly.
        var watch = CalibrationBuiltinWatch()
        watch.calibrationSet(0.4)
        var sets = 0
        for step in 0..<10_000 {
            if watch.reported(0.5, at: Double(step) / 1000) != nil { sets += 1 }
            _ = watch.reported(0.4, at: Double(step) / 1000)
        }
        XCTAssertLessThanOrEqual(sets, CalibrationBuiltinWatch.maximumSetsAgain)
    }

    // MARK: Record

    let record = CalibrationRecord(autoBrightness: true, trueTone: true, builtinBrightness: 0.6,
                                   externalKey: "4C2D-0E36-1234", externalBrightness: 0.45)

    func testTheRecordSurvivesARelaunch() {
        XCTAssertEqual(CalibrationRecord(data: record.data), record)
    }

    func testTheRecordKeepsUnknownBrightness() {
        let unknown = CalibrationRecord(autoBrightness: false, trueTone: true, builtinBrightness: nil,
                                        externalKey: "4C2D-0E36-1234", externalBrightness: nil)
        XCTAssertEqual(CalibrationRecord(data: unknown.data), unknown)
    }

    func testNoRecordOrADamagedOneRestoresNothing() {
        XCTAssertNil(CalibrationRecord(data: nil))
        XCTAssertNil(CalibrationRecord(data: Data("not a record".utf8)))
    }

    func testANewCalibrationKeepsWhatAnUnfinishedOneTurnedOff() {
        // The unfinished calibration turned both off, so the new one finds them off.
        let new = CalibrationRecord(autoBrightness: false, trueTone: false, builtinBrightness: 0.2,
                                    externalKey: "4C2D-0E36-1234", externalBrightness: 0)
        let kept = new.keeping(record)
        XCTAssertTrue(kept.autoBrightness)
        XCTAssertTrue(kept.trueTone)
    }

    func testANewCalibrationKeepsTheBrightnessFromBeforeAnUnfinishedOne() {
        let new = CalibrationRecord(autoBrightness: false, trueTone: false, builtinBrightness: 0.2,
                                    externalKey: "4C2D-0E36-1234", externalBrightness: 0)
        XCTAssertEqual(new.keeping(record), record)
    }

    func testAnotherExternalKeepsItsOwnBrightness() {
        let new = CalibrationRecord(autoBrightness: false, trueTone: false, builtinBrightness: 0.2,
                                    externalKey: "10AC-A0C4-5678", externalBrightness: 0.3)
        let kept = new.keeping(record)
        XCTAssertEqual(kept.builtinBrightness, 0.6)
        XCTAssertEqual(kept.externalKey, "10AC-A0C4-5678")
        XCTAssertEqual(kept.externalBrightness, 0.3)
    }

    func testWithoutAnUnfinishedCalibrationTheRecordStays() {
        XCTAssertEqual(record.keeping(nil), record)
    }

    // MARK: Restore

    func testWhatTheCalibrationTurnedOffComesBack() {
        let restore = record.restore(external: .own(brightness: nil))
        XCTAssertTrue(restore.autoBrightness)
        XCTAssertTrue(restore.trueTone)
        XCTAssertEqual(restore.builtinBrightness, 0.6)
        XCTAssertEqual(restore.externalBrightness, 0.45)
    }

    func testWhatWasAlreadyOffStaysOff() {
        let off = CalibrationRecord(autoBrightness: false, trueTone: false, builtinBrightness: 0.6,
                                    externalKey: "4C2D-0E36-1234", externalBrightness: 0.45)
        let restore = off.restore(external: .own(brightness: nil))
        XCTAssertFalse(restore.autoBrightness)
        XCTAssertFalse(restore.trueTone)
    }

    func testASyncedExternalFollowsTheBuiltinDisplay() {
        let restore = record.restore(external: .synced)
        XCTAssertEqual(restore.builtinBrightness, 0.6)
        XCTAssertNil(restore.externalBrightness)
    }

    func testAnExternalThatIsGoneIsNotSet() {
        XCTAssertNil(record.restore(external: .absent).externalBrightness)
    }

    func testTheSavedExternalBrightnessWinsOverTheAppsValue() {
        XCTAssertEqual(record.restore(external: .own(brightness: 0.9)).externalBrightness, 0.45)
    }

    func testAnExternalWhoseFirstReadWasPendingGetsItsValueBack() {
        // The calibration started before the first DDC read ended, so it saved no value. The read ends during the
        // calibration with the level from before it (the reads and the calibration's writes go out in order).
        let pending = CalibrationRecord(autoBrightness: true, trueTone: true, builtinBrightness: 0.6,
                                        externalKey: "4C2D-0E36-1234", externalBrightness: nil)
        XCTAssertEqual(pending.restore(external: .own(brightness: 0.7)).externalBrightness, 0.7)
    }

    func testAtALaunchAnExternalWithoutASavedValueIsLeftAlone() {
        let pending = CalibrationRecord(autoBrightness: true, trueTone: true, builtinBrightness: 0.6,
                                        externalKey: "4C2D-0E36-1234", externalBrightness: nil)
        XCTAssertNil(pending.restore(external: .own(brightness: nil)).externalBrightness)
    }
}

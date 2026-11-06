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

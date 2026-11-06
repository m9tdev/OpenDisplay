import DisplayPolicy
import XCTest

/// Two monitors of the same model without a serial number (for example a BenQ that reports serial number 0) have the
/// same key. Settings saved by display must still go to each one on its own.
final class DisplayKeyTests: XCTestCase {
    let twin = "2513-32859-0"
    let other = "4268-41234-77"

    func testASingleMonitorKeepsTheKeyItsSettingsAreSavedBy() {
        XCTAssertEqual(DisplayKey.settingsKeys([3: twin, 1: other], previous: [:]), [3: twin, 1: other])
    }

    func testTwinMonitorsGetTheirOwnKeys() {
        let keys = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        XCTAssertEqual(Set(keys.values).count, 2)
        // Settings saved by earlier versions under the shared key go to the first one.
        XCTAssertEqual(keys[3], twin)
        XCTAssertNotEqual(keys[5], twin)
    }

    func testATwinKeepsItsKeyWhenTheOtherGoesAway() {
        let both = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        let alone = DisplayKey.settingsKeys([5: twin], previous: both)
        XCTAssertEqual(alone[5], both[5])
        XCTAssertNotEqual(alone[5], twin)
    }

    func testATwinGetsItsKeyBackWhenItReturns() {
        let both = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        XCTAssertNotEqual(both[3], both[5])
        let alone = DisplayKey.settingsKeys([3: twin], previous: both)
        XCTAssertEqual(DisplayKey.settingsKeys([3: twin, 5: twin], previous: alone), both)
    }

    func testATwinThatArrivesLaterDoesNotTakeTheKeyOfTheFirst() {
        // Display 5 was the only one; display 3, the same model, is plugged in later.
        let first = DisplayKey.settingsKeys([5: twin], previous: [:])
        let keys = DisplayKey.settingsKeys([3: twin, 5: twin], previous: first)
        XCTAssertEqual(keys[5], twin)
        XCTAssertNotEqual(keys[3], twin)
        XCTAssertNotEqual(keys[3], keys[5])
    }

    func testTwinsThatBothWentAwayGetTheirOwnKeysBack() {
        let first = DisplayKey.settingsKeys([5: twin], previous: [:])
        let both = DisplayKey.settingsKeys([3: twin, 5: twin], previous: first)
        XCTAssertNotEqual(both[3], both[5])
        let none = DisplayKey.settingsKeys([:], previous: both)
        XCTAssertEqual(DisplayKey.settingsKeys([3: twin, 5: twin], previous: none), both)
    }

    func testASingleMonitorWithANewIDKeepsItsKey() {
        let before = DisplayKey.settingsKeys([3: twin], previous: [:])
        XCTAssertEqual(DisplayKey.settingsKeys([8: twin], previous: before)[8], twin)
    }

    func testAnIDNowUsedByAnotherModelGetsThatModelsKey() {
        let before = DisplayKey.settingsKeys([3: twin], previous: [:])
        XCTAssertEqual(DisplayKey.settingsKeys([3: other], previous: before)[3], other)
    }

    func testTwinsKeepTheirOwnSoftwareDimmingWhenTheyGoAwayAndReturn() {
        let keys = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        var memory = ReconnectMemory()
        let before = [ReconnectMemory.Snapshot(id: 3, key: keys[3], isEnabled: true, dimming: 0.3),
                      ReconnectMemory.Snapshot(id: 5, key: keys[5], isEnabled: true, dimming: 0.8)]
        _ = memory.refresh(before: before, after: [], turnedOnByApp: [])
        let after = [ReconnectMemory.Snapshot(id: 3, key: keys[3], isEnabled: true),
                     ReconnectMemory.Snapshot(id: 5, key: keys[5], isEnabled: true)]
        let plan = memory.refresh(before: [], after: after, turnedOnByApp: [])
        XCTAssertEqual(plan.dimming[3], 0.3)
        XCTAssertEqual(plan.dimming[5], 0.8)
    }

    func testASingleMonitorTurnedOffThatReturnsWithANewIDKeepsItsSecondKey() {
        // The app turned the monitor off at ID 3, so ID 3 stays listed with its key. The monitor comes back as ID 8.
        // This looks the same as a twin that is plugged in while the first one is off, so ID 8 gets its own key.
        let off = DisplayKey.settingsKeys([3: twin], previous: [:])
        let back = DisplayKey.settingsKeys([3: twin, 8: twin], previous: off)
        XCTAssertEqual(back[3], twin)
        XCTAssertNotEqual(back[8], twin)
        // ID 3 is no longer listed: ID 8 keeps its key, as a twin does while the other is away.
        let alone = DisplayKey.settingsKeys([8: twin], previous: back)
        XCTAssertEqual(alone[8], back[8])
        // Its sync and expanded row come along when it gets that key (see the tests below).
        XCTAssertEqual(DisplayKey.inheriting([twin], previous: off, current: back), [twin, back[8]!])
    }

    // MARK: Settings saved under the shared key

    func testATwinThatGetsItsOwnKeyKeepsTheSettingsOfTheSharedKey() {
        // Earlier versions saved brightness sync (or an expanded menu row) under the shared key, for both twins.
        let keys = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        XCTAssertEqual(DisplayKey.inheriting([twin, other], previous: [:], current: keys),
                       [twin, other, keys[5]!])
    }

    func testASettingNotSavedUnderTheSharedKeyIsNotCopied() {
        let keys = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        XCTAssertEqual(DisplayKey.inheriting([other], previous: [:], current: keys), [other])
    }

    func testAKeyThatWasAlreadySavedDoesNotGetTheSettingsAgain() {
        // The user turned sync off for the second twin only: it stays off.
        let keys = DisplayKey.settingsKeys([3: twin, 5: twin], previous: [:])
        XCTAssertEqual(DisplayKey.inheriting([twin], previous: keys, current: keys), [twin])
        // Also after it was away.
        let alone = DisplayKey.settingsKeys([3: twin], previous: keys)
        XCTAssertEqual(DisplayKey.inheriting([twin], previous: alone,
                                             current: DisplayKey.settingsKeys([3: twin, 5: twin], previous: alone)),
                       [twin])
    }
}

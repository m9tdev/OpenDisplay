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
}

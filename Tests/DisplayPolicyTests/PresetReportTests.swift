import DisplayPolicy
import XCTest

/// What Apply tells the user when a preset does not fully apply.
final class PresetReportTests: XCTestCase {
    // The built-in display 1 and an external display 3, both connected. A Dell and an LG from another desk are not.
    let builtinKey = "1552-41039-1"
    let externalKey = "2513-32859-0"
    let laptop = PresetPolicy.Mode(width: 1512, height: 982, pixelWidth: 3024, refreshRate: 120)
    let fourK = PresetPolicy.Mode(width: 1920, height: 1080, pixelWidth: 3840, refreshRate: 60)

    var connected: [PresetPolicy.Display] {
        [
            .init(id: 3, key: externalKey, name: "BenQ", isEnabled: true, mode: fourK, isMain: true),
            .init(id: 1, key: builtinKey, name: "Built-in", isEnabled: true, mode: laptop),
        ]
    }

    func entry(_ key: String, _ name: String, on: Bool, main: Bool = false) -> Preset.DisplayState {
        on ? .init(key: key, name: name, isEnabled: true, isMain: main, width: 2560, height: 1440, pixelWidth: 2560,
                   refreshRate: 60, rotation: 0)
            : .init(key: key, name: name, isEnabled: false, isMain: false, width: 0, height: 0, pixelWidth: 0,
                    refreshRate: 0, rotation: 0)
    }

    var dell: Preset.DisplayState { entry("4268-41234-77", "Dell", on: true, main: true) }
    var lg: Preset.DisplayState { entry("7789-23456-12", "LG", on: true) }

    // MARK: Nothing connected

    func testAPresetWhoseDisplayIsNotConnectedChangesNothingAndSaysWhy() {
        // An "Office" preset, applied at home: nothing would turn off, so "turns off all displays" is wrong.
        let plan = PresetPolicy.plan(Preset(name: "Office", displays: [dell]), displays: connected)
        XCTAssertTrue(plan.targets.isEmpty)
        XCTAssertEqual(plan.refusal, "Nothing changed: Dell is not connected.")
    }

    func testDisplaysThatAreNotConnectedAreNamedTogether() {
        let plan = PresetPolicy.plan(Preset(name: "Office", displays: [dell, lg]), displays: connected)
        XCTAssertEqual(plan.refusal, "Nothing changed: Dell and LG are not connected.")
    }

    func testWhenTheOnlyDisplayToTurnOnIsNotConnectedTheRefusalSaysSo() {
        // The preset turns the built-in display off and the Dell on, but the Dell is not here.
        let preset = Preset(name: "Office", displays: [dell, entry(builtinKey, "Built-in", on: false)])
        let plan = PresetPolicy.plan(preset, displays: connected)
        XCTAssertEqual(plan.refusal, "Nothing changed: Dell is not connected, and this preset turns off the other displays.")
    }

    func testAPresetThatTurnsEveryDisplayOffStillSaysSo() {
        let preset = Preset(name: "Dark", displays: [entry(externalKey, "BenQ", on: false), entry(builtinKey, "Built-in", on: false)])
        XCTAssertEqual(PresetPolicy.plan(preset, displays: connected).refusal, "This preset turns off all displays.")
    }

    func testTheRefusalOfTheDisplayCheckNamesTheDisplaysThatAreNotConnected() {
        XCTAssertEqual(PresetPolicy.turnsOffAllDisplays(notConnected: [dell]),
                       "Nothing changed: Dell is not connected, and this preset turns off the other displays.")
        XCTAssertEqual(PresetPolicy.turnsOffAllDisplays(notConnected: []), "This preset turns off all displays.")
    }

    // MARK: Part connected

    func testApplySkipsADisplayThatIsNotConnectedAndSaysSo() {
        let preset = Preset(name: "Desk", displays: [entry(externalKey, "BenQ", on: true, main: true), dell,
                                                      entry(builtinKey, "Built-in", on: true)])
        let plan = PresetPolicy.plan(preset, displays: connected)
        XCTAssertNil(plan.refusal)
        XCTAssertEqual(plan.targets.map(\.id), [3, 1])
        XCTAssertEqual(plan.notConnected.map(\.name), ["Dell"])
        XCTAssertEqual(plan.skipped, ["Skipped Dell: not connected."])
    }

    func testADisplayThatThePresetTurnsOffIsNotReportedWhenItIsNotConnected() {
        // "Laptop only" away from the desk: the BenQ it turns off is not here, which is what the preset wants.
        let preset = Preset(name: "Laptop only", displays: [entry(externalKey, "BenQ", on: false),
                                                             entry(builtinKey, "Built-in", on: true, main: true)])
        let plan = PresetPolicy.plan(preset, displays: [connected[1]])
        XCTAssertNil(plan.refusal)
        XCTAssertEqual(plan.notConnected, [])
        XCTAssertEqual(plan.skipped, [])
    }

    // MARK: Resolution

    func testASkippedResolutionNamesTheDisplayAndTheMode() {
        var state = entry(externalKey, "BenQ", on: true)
        XCTAssertEqual(PresetPolicy.resolutionNotAvailable(state),
                       "Skipped the resolution of BenQ: 2560 × 1440 at 60 Hz is not available.")
        state.width = 1920; state.height = 1080; state.pixelWidth = 3840; state.refreshRate = 59.94
        XCTAssertEqual(PresetPolicy.resolutionNotAvailable(state),
                       "Skipped the resolution of BenQ: 1920 × 1080 HiDPI at 59.94 Hz is not available.")
    }

    // MARK: Report

    func testTheReportHasEveryMessage() {
        XCTAssertEqual(PresetPolicy.report(["Skipped Dell: not connected.", "Could not turn on BenQ (error 1001)."]),
                       "Skipped Dell: not connected. Could not turn on BenQ (error 1001).")
        XCTAssertNil(PresetPolicy.report([]))
    }
}

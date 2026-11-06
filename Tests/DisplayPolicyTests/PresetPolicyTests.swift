import DisplayPolicy
import XCTest

final class PresetPolicyTests: XCTestCase {
    // The built-in display 1 and an external display 3 (a BenQ whose serial number is 0).
    let builtinKey = "1552-41039-1"
    let externalKey = "2513-32859-0"
    let laptop = PresetPolicy.Mode(width: 1512, height: 982, pixelWidth: 3024, refreshRate: 120)
    let fourK = PresetPolicy.Mode(width: 1920, height: 1080, pixelWidth: 3840, refreshRate: 60)
    let qhd = PresetPolicy.Mode(width: 2560, height: 1440, pixelWidth: 2560, refreshRate: 60)

    /// The two displays, with the external display on (and main) or off.
    func displays(externalOn: Bool, externalMode: PresetPolicy.Mode? = nil, builtinIsMain: Bool? = nil) -> [PresetPolicy.Display] {
        [
            .init(id: 3, key: externalKey, name: "BenQ", isEnabled: externalOn,
                  mode: externalOn ? externalMode ?? fourK : nil, isMain: externalOn && builtinIsMain != true,
                  brightness: externalOn ? 0.5 : nil),
            .init(id: 1, key: builtinKey, name: "Built-in", isEnabled: true, mode: laptop,
                  isMain: builtinIsMain ?? !externalOn, brightness: 0.7),
        ]
    }

    /// Saves the current setup, like Settings: a preset with the same name is replaced.
    func save(_ name: String, _ displays: [PresetPolicy.Display], to presets: inout [Preset]) {
        let preset = PresetPolicy.current(named: name, displays: displays)
        presets = presets.filter { $0.name != name } + [preset]
    }

    // MARK: Saving

    func testADisplayThatIsOffIsSavedAsOffInTheFirstPreset() {
        // First use: the external display was turned off from the menu, and no preset exists yet.
        let preset = PresetPolicy.current(named: "Laptop only", displays: displays(externalOn: false))
        XCTAssertEqual(preset.displays.map(\.key), [externalKey, builtinKey])
        XCTAssertEqual(preset.displays.first { $0.key == externalKey }?.isEnabled, false)
        XCTAssertEqual(preset.displays.first { $0.key == builtinKey }?.isEnabled, true)
    }

    func testADisplayThatIsOnWithoutAModeIsNotSavedAsOff() {
        // macOS reports no mode for a display that is on, for example while it changes: the preset must not turn it off.
        var presets: [Preset] = []
        save("Desk", displays(externalOn: true), to: &presets)
        var now = displays(externalOn: true)
        now[0].mode = nil
        let preset = PresetPolicy.current(named: "Now", displays: now)
        XCTAssertFalse(preset.displays.contains { $0.key == externalKey && !$0.isEnabled })
    }

    // MARK: Matching and applying

    func testALaptopOnlyPresetIsNotCurrentWhileTheExternalDisplayIsOn() {
        var presets: [Preset] = []
        save("Laptop only", displays(externalOn: false), to: &presets)
        // Later the external display is on again; the built-in display stays the main display.
        let now = displays(externalOn: true, builtinIsMain: true)
        XCTAssertFalse(PresetPolicy.matches(presets[0], displays: now))
    }

    func testApplyingALaptopOnlyPresetTurnsTheExternalDisplayOff() {
        var presets: [Preset] = []
        save("Laptop only", displays(externalOn: false), to: &presets)
        let targets = PresetPolicy.targets(of: presets[0], displays: displays(externalOn: true))
        XCTAssertTrue(targets.contains { $0.id == 3 && !$0.state.isEnabled })
        XCTAssertTrue(targets.contains { $0.id == 1 && $0.state.isEnabled })
    }

    func testAPresetThatTurnsADisplayOffIsCurrentWhateverPresetWasSavedLast() {
        var presets: [Preset] = []
        save("A", displays(externalOn: true, externalMode: qhd), to: &presets)
        save("Laptop", displays(externalOn: false), to: &presets)
        save("Desk", displays(externalOn: true, externalMode: fourK), to: &presets)
        // "Laptop" is applied: the external display turns off, nothing else changes.
        let laptopPreset = presets.first { $0.name == "Laptop" }!
        XCTAssertTrue(PresetPolicy.matches(laptopPreset, displays: displays(externalOn: false)))
        XCTAssertFalse(PresetPolicy.matches(presets.first { $0.name == "Desk" }!, displays: displays(externalOn: false)))
    }

    func testAPresetThatTurnsADisplayOffIsCurrentWithNoOtherPreset() {
        var presets: [Preset] = []
        save("Laptop only", displays(externalOn: false), to: &presets)
        XCTAssertTrue(PresetPolicy.matches(presets[0], displays: displays(externalOn: false)))
    }

    func testAPresetWithADisplayOnMatchesOnlyItsMode() {
        var presets: [Preset] = []
        save("Desk", displays(externalOn: true, externalMode: qhd), to: &presets)
        XCTAssertTrue(PresetPolicy.matches(presets[0], displays: displays(externalOn: true, externalMode: qhd)))
        XCTAssertFalse(PresetPolicy.matches(presets[0], displays: displays(externalOn: true, externalMode: fourK)))
        XCTAssertFalse(PresetPolicy.matches(presets[0], displays: displays(externalOn: false)))
    }

    // MARK: Saved format

    func testPresetsSavedByEarlierVersionsStillLoad() throws {
        let json = """
            [{"name":"Laptop","displays":[{"key":"2513-32859-0","name":"BenQ","isEnabled":false,"isMain":false,\
            "width":2560,"height":1440,"pixelWidth":2560,"refreshRate":60,"rotation":0,"brightness":0.5}]}]
            """
        let presets = try JSONDecoder().decode([Preset].self, from: Data(json.utf8))
        XCTAssertEqual(presets.first?.displays.first?.key, externalKey)
        XCTAssertEqual(presets.first?.displays.first?.isEnabled, false)
        // Its saved mode does not count while the display is off.
        XCTAssertTrue(PresetPolicy.matches(presets[0], displays: displays(externalOn: false)))
    }
}

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

    func testADisplayWithoutAKeyIsLeftOut() {
        // macOS does not know the display that is off, and its key was never remembered: the preset cannot name it.
        var now = displays(externalOn: false)
        now[0].key = nil
        XCTAssertEqual(PresetPolicy.current(named: "Laptop only", displays: now).displays.map(\.key), [builtinKey])
    }

    // MARK: Keys

    func testTheKeyComesFromVendorModelAndSerialNumber() {
        // The BenQ, whose serial number is 0.
        XCTAssertEqual(DisplayKey.key(vendor: 2513, model: 32859, serial: 0), externalKey)
    }

    func testADisplayIDThatMacOSDoesNotKnowHasNoKey() {
        XCTAssertNil(DisplayKey.key(vendor: .max, model: .max, serial: .max))
    }

    func testADisplayThatIsOffKeepsTheKeyItHadWhenItWasOn() {
        // While the external display 3 is on, its key is remembered.
        let keys = DisplayKey.remembered([:], reported: [1: builtinKey, 3: externalKey], keeping: [])
        // It is turned off. If macOS then no longer knows it, the remembered key names it.
        let reported = DisplayKey.key(vendor: .max, model: .max, serial: .max)
        XCTAssertEqual(DisplayKey.key(reported: reported, remembered: keys[3]), externalKey)
        // A display without a remembered key has the key macOS reports.
        XCTAssertEqual(DisplayKey.key(reported: "4268-41234-77", remembered: nil), "4268-41234-77")
        XCTAssertNil(DisplayKey.key(reported: nil, remembered: nil))
    }

    func testADisplayThatIsOffKeepsItsKeyWhenMacOSReportsAnotherOne() {
        // While the external display 3 is on, its key is remembered.
        let keys = DisplayKey.remembered([:], reported: [3: externalKey], keeping: [])
        // It is turned off, and macOS reports its vendor and model, but not its serial number.
        let reported = DisplayKey.key(vendor: 2513, model: 32859, serial: .max)
        XCTAssertEqual(DisplayKey.key(reported: reported, remembered: keys[3]), externalKey)
    }

    func testARememberedKeyFollowsTheDisplayThatHasTheID() {
        var keys = DisplayKey.remembered([:], reported: [3: externalKey], keeping: [])
        // A report without a key keeps the remembered one.
        keys = DisplayKey.remembered(keys, reported: [3: nil], keeping: [])
        XCTAssertEqual(keys, [3: externalKey])
        // Another display now has ID 3.
        keys = DisplayKey.remembered(keys, reported: [3: "4268-41234-77"], keeping: [])
        XCTAssertEqual(keys, [3: "4268-41234-77"])
    }

    func testOnlyTheKeysOfListedDisplaysStayRemembered() {
        let keys = DisplayKey.remembered([1: builtinKey, 3: externalKey, 9: "4268-41234-77"], reported: [1: builtinKey],
                                         keeping: [3])
        XCTAssertEqual(keys, [1: builtinKey, 3: externalKey])
    }

    func testAKnownDisplayThatReportsNoSerialNumberKeepsItsKey() {
        // The same key as earlier versions, so saved presets and settings still find the display.
        XCTAssertEqual(DisplayKey.key(vendor: 2513, model: 32859, serial: .max), "2513-32859-4294967295")
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

    // MARK: Identical displays

    /// Two monitors of the same model whose serial number is 0: they have the same key. Monitor 3 is on, 4 is off.
    func twins(firstOn: Bool = true) -> [PresetPolicy.Display] {
        [
            .init(id: 3, key: externalKey, name: "BenQ", isEnabled: firstOn, mode: firstOn ? fourK : nil, isMain: firstOn),
            .init(id: 4, key: externalKey, name: "BenQ", isEnabled: !firstOn, mode: firstOn ? nil : fourK, isMain: !firstOn),
        ]
    }

    func testTwoDisplaysWithTheSameKeyEachGetTheirOwnEntry() {
        let preset = PresetPolicy.current(named: "One on", displays: twins())
        let targets = PresetPolicy.targets(of: preset, displays: twins())
        XCTAssertEqual(targets.map(\.id).sorted(), [3, 4])
        XCTAssertEqual(targets.first { $0.id == 3 }?.state.isEnabled, true)
        XCTAssertEqual(targets.first { $0.id == 4 }?.state.isEnabled, false)
    }

    func testAnEntryGoesToTheDisplayItWasSavedFrom() {
        let preset = PresetPolicy.current(named: "One on", displays: twins())
        // The same displays, listed in the other order.
        let targets = PresetPolicy.targets(of: preset, displays: twins().reversed())
        XCTAssertEqual(targets.first { $0.id == 3 }?.state.isEnabled, true)
        XCTAssertEqual(targets.first { $0.id == 4 }?.state.isEnabled, false)
    }

    func testAPresetDoesNotMatchWhenTheOtherOfTwoIdenticalDisplaysIsOn() {
        let preset = PresetPolicy.current(named: "One on", displays: twins())
        XCTAssertTrue(PresetPolicy.matches(preset, displays: twins()))
        XCTAssertFalse(PresetPolicy.matches(preset, displays: twins(firstOn: false)))
    }

    func testADisplayIsNeverTurnedOnAndOffByOnePreset() {
        let on = Preset.DisplayState(key: externalKey, name: "BenQ", isEnabled: true, isMain: true, width: 1920,
                                     height: 1080, pixelWidth: 3840, refreshRate: 60, rotation: 0)
        var off = on
        off.isEnabled = false
        var builtinOff = on
        builtinOff.key = builtinKey
        builtinOff.isEnabled = false
        let changes = PresetPolicy.changes([(3, on), (3, off), (1, builtinOff)])
        XCTAssertEqual(changes, .init(turnsOn: [3], turnsOff: [1]))
    }

    func testAnEntryWhoseDisplayIDNowHasAnotherDisplayGoesToTheDisplayWithItsKey() {
        // "Desk" was saved with the external display as ID 3. Now ID 3 is another monitor, and the external display
        // has ID 5.
        let preset = PresetPolicy.current(named: "Desk", displays: displays(externalOn: true))
        let now: [PresetPolicy.Display] = [
            .init(id: 3, key: "4268-41234-77", name: "Dell", isEnabled: true, mode: qhd),
            .init(id: 5, key: externalKey, name: "BenQ", isEnabled: true, mode: fourK, isMain: true),
            displays(externalOn: true)[1],
        ]
        let targets = PresetPolicy.targets(of: preset, displays: now)
        XCTAssertEqual(targets.map(\.id), [5, 1])
        XCTAssertTrue(PresetPolicy.matches(preset, displays: now))
    }

    func testAPresetSavedByAnEarlierVersionGoesToTheFirstDisplayWithItsKey() {
        // Without saved display IDs, the entries go to the displays with their key in the order of the list.
        var preset = PresetPolicy.current(named: "One on", displays: twins())
        for index in preset.displays.indices { preset.displays[index].id = nil }
        XCTAssertEqual(PresetPolicy.targets(of: preset, displays: twins()).map(\.id), [3, 4])
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
        XCTAssertNil(presets.first?.displays.first?.id)
        // Its saved mode does not count while the display is off.
        XCTAssertTrue(PresetPolicy.matches(presets[0], displays: displays(externalOn: false)))
    }

    func testAPresetKeepsItsDisplayIDsWhenSavedAndLoaded() throws {
        let preset = PresetPolicy.current(named: "One on", displays: twins())
        XCTAssertEqual(preset.displays.map(\.id), [3, 4])
        let loaded = try JSONDecoder().decode(Preset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(loaded, preset)
    }
}

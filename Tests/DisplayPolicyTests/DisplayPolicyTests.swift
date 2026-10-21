import DisplayPolicy
import XCTest

final class DisplayPolicyTests: XCTestCase {
    // Display IDs like on the Mac where the bug happened: 1 is the built-in display, 5 the placeholder that macOS made
    // when no display was on.
    let builtin = DisplayState(id: 1, isBuiltin: true)
    let tv = DisplayState(id: 3)
    let placeholder = DisplayState(id: 5, isVirtual: true)

    // MARK: Virtual displays

    func testThePlaceholderOfMacOSIsVirtual() {
        // "unkn" and "virt": what macOS reported for the display it made when the built-in display was off.
        XCTAssertTrue(DisplayPolicy.isVirtual(vendor: 0x756E_6B6E, model: 0x7669_7274, isBuiltin: false, modeCount: 1))
    }

    func testRealDisplaysAreNotVirtual() {
        // The built-in display of a MacBook Pro, a Samsung TV, and the Philips TV of the bug (its model number is 0).
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x0610, model: 0xA04F, isBuiltin: true, modeCount: 132))
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x4C2D, model: 0x0E36, isBuiltin: false, modeCount: 58))
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x410C, model: 0, isBuiltin: false, modeCount: 135))
    }

    // MARK: Turning a display off

    func testCanTurnOffTheBuiltinDisplayWhileTheTVIsOn() {
        XCTAssertTrue(DisplayPolicy.canDisable([builtin.id], in: [builtin, tv]))
    }

    func testCannotTurnOffTheLastDisplay() {
        XCTAssertFalse(DisplayPolicy.canDisable([builtin.id], in: [builtin]))
    }

    func testAVirtualDisplayDoesNotCountAsADisplayThatIsOn() {
        XCTAssertFalse(DisplayPolicy.canDisable([builtin.id], in: [builtin, placeholder]))
        XCTAssertFalse(DisplayPolicy.canDisable([tv.id], in: [builtin.off(byUs: true), tv, placeholder]))
    }

    func testAPresetCannotTurnOffAllPhysicalDisplays() {
        // A preset turns several displays off at once.
        XCTAssertFalse(DisplayPolicy.canDisable([builtin.id, tv.id], in: [builtin, tv, placeholder]))
        XCTAssertTrue(DisplayPolicy.canDisable([builtin.id, placeholder.id], in: [builtin, tv, placeholder]))
    }

    func testCannotTurnOffTheVirtualDisplayThatIsTheOnlyOneOn() {
        XCTAssertFalse(DisplayPolicy.canDisable([placeholder.id], in: [builtin.off(byUs: true), placeholder]))
    }

    func testWithoutPhysicalDisplaysAVirtualDisplayCanTurnOffWhileAnotherIsOn() {
        // A Mac mini without a display, with two virtual displays (for screen sharing).
        let first = DisplayState(id: 7, isVirtual: true), second = DisplayState(id: 8, isVirtual: true)
        XCTAssertTrue(DisplayPolicy.canDisable([first.id], in: [first, second]))
        XCTAssertFalse(DisplayPolicy.canDisable([first.id, second.id], in: [first, second]))
    }

    // MARK: Turning a display on again

    func testTheBuiltinDisplayTurnsOnAgainAfterTheTVIsUnplugged() {
        // The bug: the built-in display was off (OpenDisplay turned it off while the TV was on), the TV was unplugged,
        // and only the placeholder of macOS was on. The built-in display was not even online.
        let off = builtin.off(byUs: true, online: false)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [off, placeholder]), [builtin.id])
    }

    func testAnOfflineDisplayWeTurnedOffIsTriedEvenIfMacOSDoesNotSayItIsBuiltin() {
        // macOS may not report the built-in display as built-in while it is offline.
        let off = DisplayState(id: 1, isOnline: false, isActive: false, isDisabledByUs: true)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [placeholder, off]), [1])
    }

    func testTheBuiltinDisplayComesFirstThenOnlineDisplaysThenTheOthers() {
        let monitor = DisplayState(id: 2, isActive: false, isDisabledByUs: true)
        let unplugged = DisplayState(id: 4, isOnline: false, isActive: false, isDisabledByUs: true)
        XCTAssertEqual(
            DisplayPolicy.displaysToRestore(in: [unplugged, monitor, builtin.off(byUs: true), placeholder]),
            [builtin.id, monitor.id, unplugged.id])
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [unplugged, monitor, placeholder]), [monitor.id, unplugged.id])
    }

    func testNothingTurnsOnWhileAPhysicalDisplayIsOn() {
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [builtin.off(byUs: true), tv]), [])
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [builtin.off(byUs: true), tv, placeholder]), [])
    }

    func testOnlyDisplaysThatOpenDisplayTurnedOffTurnOnAgain() {
        // For example a closed lid: macOS turned the built-in display off, not OpenDisplay.
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [builtin.off(byUs: false), placeholder]), [])
    }

    func testAVirtualDisplayIsNotTurnedOnAgain() {
        let virtual = DisplayState(id: 9, isActive: false, isVirtual: true, isDisabledByUs: true)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [virtual, placeholder]), [])
    }

    func testWithoutPhysicalDisplaysNothingTurnsOn() {
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [placeholder]), [])
    }
}

private extension DisplayState {
    func off(byUs: Bool, online: Bool = true) -> DisplayState {
        var state = self
        state.isActive = false
        state.isOnline = online
        state.isDisabledByUs = byUs
        return state
    }
}

/// The state on the Mac when the fix of PR #3 did not work (2026-10-21 10:33): the only online display was the
/// placeholder of macOS (ID 7, not built-in, 1920x1080), and the built-in display (ID 1) was offline and in
/// disabledDisplays. Inside OpenDisplay, macOS could not give the placeholder's display info ("error requesting display
/// info dictionary"), so its vendor and model were not "unkn" and "virt", and it counted as a physical display.
final class StandInDisplayTests: XCTestCase {
    /// The built-in display as macOS reports it while it is off: offline, with vendor and model 0xFFFFFFFF, and maybe
    /// not even built-in.
    let builtinOff = DisplayState(id: 1, isBuiltin: false, isOnline: false, isActive: false, vendor: 0xFFFF_FFFF,
                                  model: 0xFFFF_FFFF, modeCount: 0, isDisabledByUs: true)

    func standIn(vendor: UInt32, model: UInt32, modeCount: Int) -> DisplayState {
        DisplayState(id: 7, isBuiltin: false, isOnline: true, isActive: true, vendor: vendor, model: model,
                     modeCount: modeCount, isDisabledByUs: false)
    }

    func testAStandInWithAnUnreadableIdentityIsNotAPhysicalDisplay() {
        XCTAssertTrue(DisplayPolicy.isVirtual(vendor: 0xFFFF_FFFF, model: 0xFFFF_FFFF, isBuiltin: false, modeCount: 1))
        XCTAssertTrue(DisplayPolicy.isVirtual(vendor: 0, model: 0, isBuiltin: false, modeCount: 1))
    }

    func testAStandInWithoutDisplayModesIsNotAPhysicalDisplay() {
        // WindowServer: "Returning empty mode list, all CA modes are virtual".
        XCTAssertTrue(DisplayPolicy.isVirtual(vendor: 0x1234, model: 0x5678, isBuiltin: false, modeCount: 0))
    }

    func testTheBuiltinDisplayTurnsOnAgainWhenTheStandInsIdentityIsUnreadable() {
        for (vendor, model) in [(UInt32(0xFFFF_FFFF), UInt32(0xFFFF_FFFF)), (0, 0)] {
            let states = [standIn(vendor: vendor, model: model, modeCount: 1), builtinOff]
            XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1], "vendor \(vendor), model \(model)")
        }
    }

    func testTheBuiltinDisplayTurnsOnAgainWhenTheStandInHasNoDisplayModes() {
        let states = [standIn(vendor: 0x1234, model: 0x5678, modeCount: 0), builtinOff]
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1])
    }

    func testTheBuiltinDisplayTurnsOnAgainWithTheKnownPlaceholder() {
        let states = [standIn(vendor: 0x756E_6B6E, model: 0x7669_7274, modeCount: 1), builtinOff]
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1])
    }

    func testNothingTurnsOnWhileTheTVIsOn() {
        // The Philips TV of the bug: vendor 0x410C, model 0.
        let tv = DisplayState(id: 3, isBuiltin: false, isOnline: true, isActive: true, vendor: 0x410C, model: 0,
                              modeCount: 135, isDisabledByUs: false)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [tv, builtinOff]), [])
    }

    func testTheStandInDoesNotLetTheLastPhysicalDisplayTurnOff() {
        var builtinOn = builtinOff
        builtinOn.isBuiltin = true
        builtinOn.isOnline = true
        builtinOn.isActive = true
        builtinOn.isDisabledByUs = false
        let states = [standIn(vendor: 0xFFFF_FFFF, model: 0xFFFF_FFFF, modeCount: 1), builtinOn]
        XCTAssertFalse(DisplayPolicy.canDisable([1], in: states))
    }
}

/// The simulation on the Mac (2026-10-21 10:47): the built-in display turned off while it was the only display.
/// macOS made its stand-in (ID 13, "unkn"/"virt"), and for the built-in display, now unknown to it, CGDisplayIsActive,
/// CGDisplayIsOnline, and CGDisplayIsBuiltin returned -1. Read as "not 0", the built-in display counted as on, so
/// OpenDisplay logged "turn on []" and the screen stayed dark.
final class RawAnswersTests: XCTestCase {
    let standIn = DisplayReport(id: 13, isBuiltin: 0, isOnline: 1, isActive: 1, vendor: 0x756E_6B6E,
                                model: 0x7669_7274, modeCount: 1)
    let builtinOff = DisplayReport(id: 1, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF,
                                   model: 0xFFFF_FFFF, modeCount: 0)

    func testATurnedOffBuiltinDisplayThatMacOSAnswersMinusOneForIsInactive() {
        let states = DisplayPolicy.states(online: [13], active: [13], reports: [standIn, builtinOff], disabled: [1])
        XCTAssertEqual(states.first { $0.id == 1 }?.isActive, false)
        XCTAssertEqual(states.first { $0.id == 1 }?.isOnline, false)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1])
    }

    func testOnlyAnAnswerOfOneMeansBuiltin() {
        let states = DisplayPolicy.states(online: [13], active: [13], reports: [standIn, builtinOff], disabled: [1])
        XCTAssertEqual(states.first { $0.id == 1 }?.isBuiltin, false)
        let on = DisplayReport(id: 1, isBuiltin: 1, isOnline: 1, isActive: 1, vendor: 0x0610, model: 0xA04F,
                               modeCount: 60)
        XCTAssertEqual(DisplayPolicy.states(online: [1], active: [1], reports: [on], disabled: []).first?.isBuiltin, true)
    }

    func testActiveAndOnlineComeFromTheLists() {
        // The lists are the truth, whatever the single answers say.
        let tv = DisplayReport(id: 3, isBuiltin: 0, isOnline: 0, isActive: 0, vendor: 0x410C, model: 0, modeCount: 135)
        let states = DisplayPolicy.states(online: [3], active: [3], reports: [tv, builtinOff], disabled: [1])
        XCTAssertEqual(states.first { $0.id == 3 }?.isActive, true)
        XCTAssertEqual(states.first { $0.id == 3 }?.isOnline, true)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [])
    }

    func testTheBuiltinDisplayCannotTurnOffWhenOnlyTheStandInWouldStayOn() {
        let on = DisplayReport(id: 1, isBuiltin: 1, isOnline: 1, isActive: 1, vendor: 0x0610, model: 0xA04F,
                               modeCount: 60)
        let states = DisplayPolicy.states(online: [1, 13], active: [1, 13], reports: [on, standIn], disabled: [])
        XCTAssertFalse(DisplayPolicy.canDisable([1], in: states))
    }
}

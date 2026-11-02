import DisplayPolicy
import XCTest

final class DisplayPolicyTests: XCTestCase {
    // 1 is the built-in display, 3 a TV, and 5 the placeholder display that macOS makes when no display is on.
    let builtin = DisplayState(id: 1, isBuiltin: true)
    let tv = DisplayState(id: 3)
    let placeholder = DisplayState(id: 5, isVirtual: true)

    // MARK: Virtual displays

    func testThePlaceholderOfMacOSIsVirtual() {
        // "unkn" and "virt": the vendor and model of the display that macOS makes when no display is on.
        XCTAssertTrue(DisplayPolicy.isVirtual(vendor: 0x756E_6B6E, model: 0x7669_7274, isBuiltin: false))
    }

    func testRealDisplaysAreNotVirtual() {
        // The built-in display of a MacBook Pro, a Samsung TV, and a Philips TV whose model number is 0.
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x0610, model: 0xA04F, isBuiltin: true))
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x4C2D, model: 0x0E36, isBuiltin: false))
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x410C, model: 0, isBuiltin: false))
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
        // OpenDisplay turned the built-in display off while the TV was on, then the TV was unplugged: only the
        // placeholder of macOS is on, and the built-in display is not even online.
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

/// Display states built with the vendor and model initializer, while the built-in display is off.
final class StandInDisplayTests: XCTestCase {
    /// The built-in display as macOS reports it while it is off: offline, with vendor and model 0xFFFFFFFF.
    let builtinOff = DisplayState(id: 1, isBuiltin: true, isOnline: false, isActive: false, vendor: 0xFFFF_FFFF,
                                  model: 0xFFFF_FFFF, isDisabledByUs: true)

    func testTheBuiltinDisplayTurnsOnAgainWhileOnlyTheStandInIsOn() {
        let standIn = DisplayState(id: 7, isBuiltin: false, isOnline: true, isActive: true, vendor: 0x756E_6B6E,
                                   model: 0x7669_7274, isDisabledByUs: false)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [standIn, builtinOff]), [1])
    }

    func testNothingTurnsOnWhileTheTVIsOn() {
        // A Philips TV: vendor 0x410C, model 0.
        let tv = DisplayState(id: 3, isBuiltin: false, isOnline: true, isActive: true, vendor: 0x410C, model: 0,
                              isDisabledByUs: false)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: [tv, builtinOff]), [])
    }
}

/// Display states built from the raw answers of macOS. When the built-in display is off and no other display is on,
/// macOS shows its stand-in display ("unkn"/"virt"), and for the built-in display, which it does not know then,
/// CGDisplayIsActive, CGDisplayIsOnline, and CGDisplayIsBuiltin return -1. That must not count as on.
final class RawAnswersTests: XCTestCase {
    let standIn = DisplayReport(id: 13, isBuiltin: 0, isOnline: 1, isActive: 1, vendor: 0x756E_6B6E,
                                model: 0x7669_7274)
    let builtinOff = DisplayReport(id: 1, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF,
                                   model: 0xFFFF_FFFF)

    func testATurnedOffBuiltinDisplayThatMacOSAnswersMinusOneForIsInactive() {
        let states = DisplayPolicy.states(online: [13], active: [13], reports: [standIn, builtinOff], disabled: [1])
        XCTAssertEqual(states.first { $0.id == 1 }?.isActive, false)
        XCTAssertEqual(states.first { $0.id == 1 }?.isOnline, false)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [1])
    }

    func testOnlyAnAnswerOfOneMeansBuiltin() {
        let states = DisplayPolicy.states(online: [13], active: [13], reports: [standIn, builtinOff], disabled: [1])
        XCTAssertEqual(states.first { $0.id == 1 }?.isBuiltin, false)
        let on = DisplayReport(id: 1, isBuiltin: 1, isOnline: 1, isActive: 1, vendor: 0x0610, model: 0xA04F)
        XCTAssertEqual(DisplayPolicy.states(online: [1], active: [1], reports: [on], disabled: []).first?.isBuiltin, true)
    }

    func testActiveAndOnlineComeFromTheLists() {
        // The lists are the truth, whatever the single answers say.
        let tv = DisplayReport(id: 3, isBuiltin: 0, isOnline: 0, isActive: 0, vendor: 0x410C, model: 0)
        let states = DisplayPolicy.states(online: [3], active: [3], reports: [tv, builtinOff], disabled: [1])
        XCTAssertEqual(states.first { $0.id == 3 }?.isActive, true)
        XCTAssertEqual(states.first { $0.id == 3 }?.isOnline, true)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [])
    }

    func testTheBuiltinDisplayCannotTurnOffWhenOnlyTheStandInWouldStayOn() {
        let on = DisplayReport(id: 1, isBuiltin: 1, isOnline: 1, isActive: 1, vendor: 0x0610, model: 0xA04F)
        let states = DisplayPolicy.states(online: [1, 13], active: [1, 13], reports: [on, standIn], disabled: [])
        XCTAssertFalse(DisplayPolicy.canDisable([1], in: states))
    }
}

/// While the built-in display is off, macOS answers -1 to CGDisplayIsBuiltin, so the built-in flag comes from when the
/// display was last on.
final class RememberedBuiltinTests: XCTestCase {
    let standIn = DisplayReport(id: 13, isBuiltin: 0, isOnline: 1, isActive: 1, vendor: 0x756E_6B6E, model: 0x7669_7274)
    /// A built-in display with a higher ID than an external display, both off.
    let builtinOff = DisplayReport(id: 4, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF,
                                   model: 0xFFFF_FFFF)
    let monitorOff = DisplayReport(id: 2, isBuiltin: -1, isOnline: -1, isActive: -1, vendor: 0xFFFF_FFFF,
                                   model: 0xFFFF_FFFF)

    func testARememberedBuiltinDisplayThatIsOffTurnsOnFirst() {
        let states = DisplayPolicy.states(online: [13], active: [13], reports: [standIn, monitorOff, builtinOff],
                                          disabled: [2, 4], builtins: [4])
        XCTAssertEqual(states.first { $0.id == 4 }?.isBuiltin, true)
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [4, 2])
    }

    func testWithoutTheMemoryTheLowestIDComesFirst() {
        let states = DisplayPolicy.states(online: [13], active: [13], reports: [standIn, monitorOff, builtinOff],
                                          disabled: [2, 4])
        XCTAssertEqual(DisplayPolicy.displaysToRestore(in: states), [2, 4])
    }

    func testAnAnswerOfMacOSWinsOverTheMemory() {
        // A display ID that was built-in, now used by an external display that is on.
        let external = DisplayReport(id: 4, isBuiltin: 0, isOnline: 1, isActive: 1, vendor: 0x410C, model: 0)
        let states = DisplayPolicy.states(online: [4], active: [4], reports: [external], disabled: [], builtins: [4])
        XCTAssertEqual(states.first?.isBuiltin, false)
    }
}

/// Which displays are remembered as built-in, from the answers of CGDisplayIsBuiltin for the displays that are on.
final class BuiltinMemoryTests: XCTestCase {
    func testAnAnswerOfOneAddsTheDisplay() {
        XCTAssertEqual(DisplayPolicy.rememberedBuiltins([], answers: [1: 1, 3: 0]), [1])
    }

    func testAnAnswerOfZeroRemovesTheDisplay() {
        // The ID was the built-in display before, and now belongs to an external display.
        XCTAssertEqual(DisplayPolicy.rememberedBuiltins([1, 4], answers: [4: 0]), [1])
    }

    func testAnUnknownAnswerKeepsTheMemory() {
        XCTAssertEqual(DisplayPolicy.rememberedBuiltins([1], answers: [1: -1]), [1])
        XCTAssertEqual(DisplayPolicy.rememberedBuiltins([], answers: [1: -1]), [])
    }

    func testIsBuiltinUsesTheMemoryOnlyForAnUnknownAnswer() {
        XCTAssertTrue(DisplayPolicy.isBuiltin(answer: 1, id: 1, builtins: []))
        XCTAssertFalse(DisplayPolicy.isBuiltin(answer: 0, id: 1, builtins: [1]))
        XCTAssertTrue(DisplayPolicy.isBuiltin(answer: -1, id: 1, builtins: [1]))
        XCTAssertFalse(DisplayPolicy.isBuiltin(answer: -1, id: 2, builtins: [1]))
    }
}

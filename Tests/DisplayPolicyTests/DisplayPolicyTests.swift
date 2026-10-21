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
        XCTAssertTrue(DisplayPolicy.isVirtual(vendor: 0x756E_6B6E, model: 0x7669_7274, isBuiltin: false))
    }

    func testRealDisplaysAreNotVirtual() {
        // The built-in display of a MacBook Pro, and a TV (Samsung).
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x0610, model: 0xA04F, isBuiltin: true))
        XCTAssertFalse(DisplayPolicy.isVirtual(vendor: 0x4C2D, model: 0x0E36, isBuiltin: false))
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

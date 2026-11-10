import DisplayPolicy
import XCTest

/// External displays paired with the DDC services in the registry.
final class DDCPairingTests: XCTestCase {
    typealias Display = DDCPairing.Display
    typealias Service = DDCPairing.Service

    /// A monitor model without a serial number (macOS reports 0).
    func twinService(_ entry: UInt64?) -> Service {
        Service(entry: entry, vendor: 0x4C2D, model: 0x0E36, serial: nil)
    }

    func twin(_ id: UInt32, current: UInt64? = nil) -> Display {
        Display(id: id, vendor: 0x4C2D, model: 0x0E36, serial: 0, current: current)
    }

    /// The display ID that gets each entry ID.
    func pairs(_ displays: [Display], _ services: [Service]) -> [UInt32: UInt64?] {
        DDCPairing.pair(displays, with: services).mapValues { services[$0].entry }
    }

    func testTwinsArePairedInOrder() {
        XCTAssertEqual(pairs([twin(2), twin(3)], [twinService(10), twinService(11)]), [2: 10, 3: 11])
    }

    /// The app turned twin 2 off, and its service stays in the registry before the service of twin 3: twin 3 keeps
    /// its own, so its slider does not control the monitor that is off.
    func testATwinKeepsItsServiceWhenTheOtherTwinIsOff() {
        XCTAssertEqual(pairs([twin(3, current: 11)], [twinService(10), twinService(11)]), [3: 11])
    }

    func testTwinsKeepTheirServicesWhenTheRegistryOrderChanges() {
        XCTAssertEqual(pairs([twin(2, current: 10), twin(3, current: 11)], [twinService(11), twinService(10)]),
                       [2: 10, 3: 11])
    }

    /// The current service went away (unplugged, or made again after a wake): the display gets a new one.
    func testADisplayWhoseServiceIsGoneGetsANewOne() {
        XCTAssertEqual(pairs([twin(2, current: 10)], [twinService(12)]), [2: 12])
    }

    /// The current entry now reports another monitor: it is not kept, and the display gets its own.
    func testACurrentServiceOfAnotherMonitorIsNotKept() {
        let other = Service(entry: 10, vendor: 0x10AC, model: 0x4321, serial: 5)
        let own = Service(entry: 12, vendor: 0x10AC, model: 0x4321, serial: 6)
        let display = Display(id: 2, vendor: 0x10AC, model: 0x4321, serial: 6, current: 10)
        XCTAssertEqual(pairs([display], [other, own]), [2: 12])
    }

    func testTheSerialNumberTellsMonitorsOfOneModelApart() {
        let first = Service(entry: 10, vendor: 1, model: 2, serial: 100)
        let second = Service(entry: 11, vendor: 1, model: 2, serial: 200)
        let display = Display(id: 2, vendor: 1, model: 2, serial: 200)
        XCTAssertEqual(pairs([display], [first, second]), [2: 11])
    }

    /// A framebuffer that reports nothing: one display and one service left belong together.
    func testOneDisplayAndOneServiceLeftBelongTogether() {
        let unknown = Service(entry: 10, vendor: nil, model: nil, serial: nil)
        XCTAssertEqual(pairs([twin(2)], [unknown]), [2: 10])
    }
}

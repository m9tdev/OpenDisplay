import CoreGraphics
import Foundation
import IOKit

/// One external display that answers DDC/CI over an IOAVService.
final class DDCService: @unchecked Sendable {
    let service: CFTypeRef
    private let queue = DispatchQueue(label: "dev.m9t.opendisplay.ddc")
    private let lock = NSLock()
    /// Newest value to write for each VCP code.
    private var pending: [UInt8: UInt16] = [:]
    private var busy = false

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    init(service: CFTypeRef) {
        self.service = service
    }

    /// Queue a write. If a write is in progress, only the newest value for each VCP code is sent next.
    func setLater(vcp: UInt8, value: UInt16) {
        lock.lock()
        pending[vcp] = value
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()
        queue.async { self.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let (vcp, value) = pending.first else {
                busy = false
                lock.unlock()
                return
            }
            pending[vcp] = nil
            lock.unlock()
            _ = write(vcp: vcp, value: value)
        }
    }

    /// Read a VCP value off the main thread. Calls back on the main queue.
    func readLater(vcp: UInt8, completion: @escaping @Sendable ((current: UInt16, max: UInt16)?) -> Void) {
        queue.async {
            let result = self.read(vcp: vcp)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Read the capabilities off the main thread. Calls back on the main queue.
    func capabilitiesLater(completion: @escaping @Sendable (String?) -> Void) {
        queue.async {
            let result = self.capabilities()
            DispatchQueue.main.async { completion(result) }
        }
    }

    @discardableResult
    func write(vcp: UInt8, value: UInt16) -> Bool {
        guard let writeI2C = PrivateAPI.avServiceWriteI2C else { return false }
        var packet: [UInt8] = [0x84, 0x03, vcp, UInt8(value >> 8), UInt8(value & 0xFF), 0]
        packet[5] = Self.checksum(packet[0..<5])
        var ok = false
        // Some monitors drop the first packet, so send it twice.
        for _ in 0..<2 {
            usleep(10_000)
            let result = packet.withUnsafeMutableBytes {
                writeI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            ok = ok || result == kIOReturnSuccess
        }
        return ok
    }

    func read(vcp: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C = PrivateAPI.avServiceWriteI2C, let readI2C = PrivateAPI.avServiceReadI2C else { return nil }
        var request: [UInt8] = [0x82, 0x01, vcp, 0]
        request[3] = Self.checksum(request[0..<3])

        for _ in 0..<4 {
            usleep(10_000)
            let sent = request.withUnsafeMutableBytes {
                writeI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            guard sent == kIOReturnSuccess else { continue }
            usleep(50_000)

            var reply = [UInt8](repeating: 0, count: 12)
            let received = reply.withUnsafeMutableBytes {
                readI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
            }
            // Reply layout: 6E 88 02 <result> <vcp> <type> <maxHi> <maxLo> <curHi> <curLo> <checksum>
            guard received == kIOReturnSuccess, reply[2] == 0x02, reply[3] == 0x00, reply[4] == vcp else { continue }
            let max = UInt16(reply[6]) << 8 | UInt16(reply[7])
            let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
            return (current, max)
        }
        return nil
    }

    /// The monitor's capabilities string, for example `(prot(monitor)type(LCD)vcp(10 12 14(05 08) 60(0F 11)))`.
    /// The monitor sends it in parts of up to 32 bytes.
    func capabilities() -> String? {
        guard let writeI2C = PrivateAPI.avServiceWriteI2C, let readI2C = PrivateAPI.avServiceReadI2C else { return nil }
        var text: [UInt8] = []
        while text.count < 4096 {
            let offset = UInt16(text.count)
            var request: [UInt8] = [0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF), 0]
            request[4] = Self.checksum(request[0..<4])
            var part: [UInt8]?
            for _ in 0..<5 {
                usleep(10_000)
                let sent = request.withUnsafeMutableBytes {
                    writeI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
                }
                guard sent == kIOReturnSuccess else { continue }
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: 38)
                let received = reply.withUnsafeMutableBytes {
                    readI2C(service, Self.chipAddress, Self.dataAddress, $0.baseAddress!, UInt32($0.count))
                }
                // Reply layout: 6E <0x80 | length> E3 <offsetHi> <offsetLo> <data ...> <checksum>
                let length = Int(reply[1] & 0x7F) - 3
                guard received == kIOReturnSuccess, reply[2] == 0xE3, (0...32).contains(length),
                      UInt16(reply[3]) << 8 | UInt16(reply[4]) == offset else { continue }
                part = Array(reply[5..<(5 + length)])
                break
            }
            guard let part else { return nil }
            text += part
            if part.isEmpty || part.contains(0) { break }
        }
        return String(decoding: text.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func checksum(_ bytes: ArraySlice<UInt8>) -> UInt8 {
        bytes.reduce(UInt8(0x6E ^ 0x51), ^)
    }
}

enum VCP {
    static let brightness: UInt8 = 0x10
    static let volume: UInt8 = 0x62
    /// 1 = muted, 2 = not muted.
    static let mute: UInt8 = 0x8D
    static let contrast: UInt8 = 0x12
    static let colorPreset: UInt8 = 0x14
    static let input: UInt8 = 0x60

    /// The VCP codes in a capabilities string, with their allowed values (empty for a range, like brightness).
    static func parse(capabilities: String) -> [UInt8: [UInt8]] {
        guard let start = capabilities.range(of: "vcp(") else { return [:] }
        var result: [UInt8: [UInt8]] = [:]
        var depth = 0
        var current: UInt8?
        var token = ""
        func endToken() {
            defer { token = "" }
            guard let value = UInt8(token, radix: 16) else { return }
            if depth == 0 {
                current = value
                result[value] = result[value] ?? []
            } else if let current {
                result[current, default: []].append(value)
            }
        }
        for character in capabilities[start.upperBound...] {
            switch character {
            case "(":
                endToken()
                depth += 1
            case ")":
                endToken()
                if depth == 0 { return result }
                depth -= 1
            case " ":
                endToken()
            default:
                token.append(character)
            }
        }
        return result
    }
}

/// Finds the DDC service for each external display.
enum DDCDiscovery {
    private struct Framebuffer {
        var vendor: UInt32?
        var model: UInt32?
        var serial: UInt32?
    }

    private struct Candidate {
        var framebuffer: Framebuffer
        /// Retained. Released after matching.
        var entry: io_service_t
    }

    static func services(for displays: [CGDirectDisplayID]) -> [CGDirectDisplayID: DDCService] {
        let externals = displays.filter { CGDisplayIsBuiltin($0) == 0 }
        guard let create = PrivateAPI.avServiceCreate, !externals.isEmpty else { return [:] }
        var candidates: [Candidate] = []

        var iterator = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iterator) }

        // The registry lists each framebuffer before its DCPAVServiceProxy, so pair them in order.
        var lastFramebuffer: Framebuffer?
        let name = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { name.deallocate() }

        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard IORegistryEntryGetName(entry, name) == KERN_SUCCESS else { continue }
            switch String(cString: name) {
            case "AppleCLCD2", "IOMobileFramebufferShim":
                lastFramebuffer = framebuffer(entry)
            case "DCPAVServiceProxy":
                guard property(entry, "Location") as? String == "External", let framebuffer = lastFramebuffer else { continue }
                IOObjectRetain(entry)
                candidates.append(Candidate(framebuffer: framebuffer, entry: entry))
                lastFramebuffer = nil
            default:
                continue
            }
        }

        defer { candidates.forEach { IOObjectRelease($0.entry) } }

        // Only open a service for a display that is on. Opening one for a display that is off may wake it.
        func service(_ candidate: Candidate) -> DDCService? {
            create(kCFAllocatorDefault, candidate.entry).map { DDCService(service: $0.takeRetainedValue()) }
        }

        var result: [CGDirectDisplayID: DDCService] = [:]
        var unused = candidates
        for display in externals {
            let match = unused.firstIndex {
                $0.framebuffer.vendor == CGDisplayVendorNumber(display)
                    && $0.framebuffer.model == CGDisplayModelNumber(display)
                    && ($0.framebuffer.serial == nil || $0.framebuffer.serial == CGDisplaySerialNumber(display))
            }
            if let match {
                result[display] = service(unused.remove(at: match))
            }
        }
        // Fallback: one display left and one service left, so they must belong together.
        let unmatched = externals.filter { result[$0] == nil }
        if unmatched.count == 1, unused.count == 1 {
            result[unmatched[0]] = service(unused[0])
        }
        return result
    }

    private static func framebuffer(_ entry: io_registry_entry_t) -> Framebuffer {
        let attributes = (property(entry, "DisplayAttributes") as? [String: Any])?["ProductAttributes"] as? [String: Any]
        return Framebuffer(
            vendor: (attributes?["LegacyManufacturerID"] as? NSNumber)?.uint32Value,
            model: (attributes?["ProductID"] as? NSNumber)?.uint32Value,
            serial: (attributes?["SerialNumber"] as? NSNumber)?.uint32Value
        )
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

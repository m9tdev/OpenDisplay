/// Pairs the external displays that are on with the DDC services in the I/O Registry.
///
/// Each service follows a framebuffer that reports the vendor, model and serial number of its monitor. Two monitors of
/// the same model without a serial number report the same, so they are paired in list order, and that order can change:
/// for example, a twin the app turned off can keep its service in the registry. So a display keeps the service it has
/// while that service is still there and still reports its monitor.
public enum DDCPairing {
    /// An external display that is on.
    public struct Display: Equatable, Sendable {
        /// `CGDirectDisplayID`.
        public var id: UInt32
        public var vendor: UInt32
        public var model: UInt32
        public var serial: UInt32
        /// The registry entry ID of the service the display has now, if any.
        public var current: UInt64?

        public init(id: UInt32, vendor: UInt32, model: UInt32, serial: UInt32, current: UInt64? = nil) {
            self.id = id
            self.vendor = vendor
            self.model = model
            self.serial = serial
            self.current = current
        }
    }

    /// A DDC service in the registry, with what its framebuffer reports (`nil` when it does not).
    public struct Service: Equatable, Sendable {
        /// The registry entry ID, `nil` if it could not be read.
        public var entry: UInt64?
        public var vendor: UInt32?
        public var model: UInt32?
        public var serial: UInt32?

        public init(entry: UInt64?, vendor: UInt32?, model: UInt32?, serial: UInt32?) {
            self.entry = entry
            self.vendor = vendor
            self.model = model
            self.serial = serial
        }
    }

    /// The index in `services` of the service of each display. A display first keeps its current service, if that
    /// matches it; the others get the first matching service left, in order. If one display and one service are left
    /// unmatched, they belong together.
    public static func pair(_ displays: [Display], with services: [Service]) -> [UInt32: Int] {
        var result: [UInt32: Int] = [:]
        var unused = Array(services.indices)
        func matches(_ display: Display, _ service: Service) -> Bool {
            service.vendor == display.vendor && service.model == display.model
                && (service.serial == nil || service.serial == display.serial)
        }
        for display in displays {
            guard let current = display.current, let match = unused.firstIndex(where: {
                services[$0].entry == current && matches(display, services[$0])
            }) else { continue }
            result[display.id] = unused.remove(at: match)
        }
        for display in displays where result[display.id] == nil {
            if let match = unused.firstIndex(where: { matches(display, services[$0]) }) {
                result[display.id] = unused.remove(at: match)
            }
        }
        let unmatched = displays.filter { result[$0.id] == nil }
        if unmatched.count == 1, unused.count == 1 {
            result[unmatched[0].id] = unused[0]
        }
        return result
    }
}

/// A saved display setup, for example "Desk" or "Laptop only".
public struct Preset: Codable, Equatable, Sendable {
    public struct DisplayState: Codable, Equatable, Sendable {
        /// The stable key of the display (see `DisplayKey`).
        public var key: String
        public var name: String
        public var isEnabled: Bool
        public var isMain: Bool
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var refreshRate: Double
        public var rotation: Int
        public var brightness: Double?
        /// The display ID when the preset was saved. Two displays of the same model without a serial number have the
        /// same key, so this tells them apart while their IDs stay the same. `nil` in presets saved by earlier versions.
        public var id: UInt32?

        public init(key: String, name: String, isEnabled: Bool, isMain: Bool, width: Int, height: Int, pixelWidth: Int,
                    refreshRate: Double, rotation: Int, brightness: Double? = nil, id: UInt32? = nil) {
            self.id = id
            self.key = key
            self.name = name
            self.isEnabled = isEnabled
            self.isMain = isMain
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.refreshRate = refreshRate
            self.rotation = rotation
            self.brightness = brightness
        }
    }

    public var name: String
    public var displays: [DisplayState]

    public init(name: String, displays: [DisplayState]) {
        self.name = name
        self.displays = displays
    }
}

/// How presets are saved, matched and applied. Plain values, so the decisions can be tested without displays.
public enum PresetPolicy {
    /// A display mode, as `CGDisplayMode` reports it.
    public struct Mode: Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var refreshRate: Double

        public init(width: Int, height: Int, pixelWidth: Int, refreshRate: Double) {
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.refreshRate = refreshRate
        }
    }

    /// One display in the list of the app, as it is now.
    public struct Display: Equatable, Sendable {
        /// `CGDirectDisplayID`.
        public var id: UInt32
        /// The stable key of the display (see `DisplayKey`). `nil` when it is not known: such a display is left out of
        /// presets.
        public var key: String?
        public var name: String
        public var isEnabled: Bool
        /// The current mode, `nil` when macOS does not report one (for example while the display is off).
        public var mode: Mode?
        public var isMain: Bool
        public var rotation: Int
        public var brightness: Double?

        public init(id: UInt32, key: String?, name: String, isEnabled: Bool, mode: Mode?, isMain: Bool = false,
                    rotation: Int = 0, brightness: Double? = nil) {
            self.id = id
            self.key = key
            self.name = name
            self.isEnabled = isEnabled
            self.mode = mode
            self.isMain = isMain
            self.rotation = rotation
            self.brightness = brightness
        }
    }

    /// The current setup of `displays`, as a preset. A display that is off is saved as off, so the preset turns it
    /// off. Its mode is not saved: macOS does not report one, and turning a display off does not use it. A display
    /// that is on but reports no mode is left out, so the preset does not change it, and so is a display without a
    /// key.
    public static func current(named name: String, displays: [Display]) -> Preset {
        Preset(name: name, displays: displays.compactMap(state))
    }

    /// The preset entry for a display as it is now, `nil` if it cannot have one (see `current`).
    static func state(of display: Display) -> Preset.DisplayState? {
        guard let key = display.key else { return nil }
        guard display.isEnabled else {
            return .init(key: key, name: display.name, isEnabled: false, isMain: false,
                         width: 0, height: 0, pixelWidth: 0, refreshRate: 0, rotation: 0, id: display.id)
        }
        guard let mode = display.mode else { return nil }
        return .init(
            key: key, name: display.name, isEnabled: true, isMain: display.isMain,
            width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, refreshRate: mode.refreshRate,
            rotation: display.rotation, brightness: display.brightness, id: display.id
        )
    }

    /// True when `displays` match the preset now: each entry of the preset has its own display (see `targets`), on or
    /// off as in the preset, and a display that is on has its mode, rotation and main display. Brightness, names and
    /// display IDs do not count, nor the mode saved for a display that is off (presets saved by earlier versions
    /// have one).
    public static func matches(_ preset: Preset, displays: [Display]) -> Bool {
        let targets = targets(of: preset, displays: displays)
        guard targets.count == preset.displays.count else { return false }
        return targets.allSatisfy { id, state in
            guard let display = displays.first(where: { $0.id == id }), let now = self.state(of: display) else {
                return false
            }
            guard state.isEnabled else { return !now.isEnabled }
            var a = now, b = state
            a.name = ""; b.name = ""; a.brightness = nil; b.brightness = nil; a.id = nil; b.id = nil
            return a == b
        }
    }

    /// The displays a preset changes, with their states, in the order of the preset. Each display gets at most one
    /// entry: an entry goes to the display it was saved from if that display still has the same ID and key, else to
    /// the first other display with its key. So two displays with the same key (the same model, without a serial
    /// number) each get their own entry. Entries without a display are left out.
    public static func targets(of preset: Preset, displays: [Display]) -> [(id: UInt32, state: Preset.DisplayState)] {
        var chosen: [Int: UInt32] = [:]
        var used: Set<UInt32> = []
        for (index, state) in preset.displays.enumerated() {
            guard let id = state.id, !used.contains(id),
                  displays.contains(where: { $0.id == id && $0.key == state.key }) else { continue }
            chosen[index] = id
            used.insert(id)
        }
        for (index, state) in preset.displays.enumerated() where chosen[index] == nil {
            guard let display = displays.first(where: { $0.key == state.key && !used.contains($0.id) }) else { continue }
            chosen[index] = display.id
            used.insert(display.id)
        }
        return preset.displays.indices.compactMap { index in chosen[index].map { ($0, preset.displays[index]) } }
    }

    /// The displays that Apply turns on and off.
    public struct Changes: Equatable, Sendable {
        public var turnsOn: Set<UInt32>
        public var turnsOff: Set<UInt32>

        public init(turnsOn: Set<UInt32>, turnsOff: Set<UInt32>) {
            self.turnsOn = turnsOn
            self.turnsOff = turnsOff
        }
    }

    /// The displays that `targets` turn on and off. A display that would be both stays on: a display that is off is
    /// never turned off as well (`targets` gives each display one entry, so this is only a safeguard).
    public static func changes(_ targets: [(id: UInt32, state: Preset.DisplayState)]) -> Changes {
        let turnsOn = Set(targets.filter(\.state.isEnabled).map(\.id))
        let turnsOff = Set(targets.filter { !$0.state.isEnabled }.map(\.id)).subtracting(turnsOn)
        return Changes(turnsOn: turnsOn, turnsOff: turnsOff)
    }
}

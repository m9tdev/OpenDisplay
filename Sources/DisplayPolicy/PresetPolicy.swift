/// A saved display setup, for example "Desk" or "Laptop only".
public struct Preset: Codable, Equatable, Sendable {
    public struct DisplayState: Codable, Equatable, Sendable {
        /// The display's stable key (vendor, model and serial number; see `PresetPolicy.Display.key`).
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

        public init(key: String, name: String, isEnabled: Bool, isMain: Bool, width: Int, height: Int, pixelWidth: Int,
                    refreshRate: Double, rotation: Int, brightness: Double? = nil) {
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
        /// The stable key of the display.
        public var key: String
        public var name: String
        public var isEnabled: Bool
        /// The current mode, `nil` when macOS does not report one (for example while the display is off).
        public var mode: Mode?
        public var isMain: Bool
        public var rotation: Int
        public var brightness: Double?

        public init(id: UInt32, key: String, name: String, isEnabled: Bool, mode: Mode?, isMain: Bool = false,
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
    /// that is on but reports no mode is left out, so the preset does not change it.
    public static func current(named name: String, displays: [Display]) -> Preset {
        Preset(name: name, displays: displays.compactMap { display in
            guard display.isEnabled else {
                return .init(key: display.key, name: display.name, isEnabled: false, isMain: false,
                             width: 0, height: 0, pixelWidth: 0, refreshRate: 0, rotation: 0)
            }
            guard let mode = display.mode else { return nil }
            return .init(
                key: display.key, name: display.name, isEnabled: true, isMain: display.isMain,
                width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, refreshRate: mode.refreshRate,
                rotation: display.rotation, brightness: display.brightness
            )
        })
    }

    /// True when `displays` match the preset now: each display in the preset is there, on or off as in the preset,
    /// and a display that is on has its mode, rotation and main display. Brightness and names do not count, nor the
    /// mode saved for a display that is off (presets saved by earlier versions have one).
    public static func matches(_ preset: Preset, displays: [Display]) -> Bool {
        let current = current(named: "", displays: displays)
        return preset.displays.allSatisfy { state in
            current.displays.contains { now in
                guard state.isEnabled else { return now.key == state.key && !now.isEnabled }
                var a = now, b = state
                a.name = ""; b.name = ""; a.brightness = nil; b.brightness = nil
                return a == b
            }
        }
    }

    /// The displays a preset changes, with their states. Entries for displays that are not in `displays` are left
    /// out.
    public static func targets(of preset: Preset, displays: [Display]) -> [(id: UInt32, state: Preset.DisplayState)] {
        preset.displays.compactMap { state in
            displays.first { $0.key == state.key }.map { ($0.id, state) }
        }
    }
}

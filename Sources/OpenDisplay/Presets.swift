import AppKit
import CoreGraphics
import DisplayPolicy
import Observation

/// A saved display setup, for example "Desk" or "Laptop only".
struct Preset: Codable, Equatable {
    struct DisplayState: Codable, Equatable {
        /// `Display.stableKey`.
        var key: String
        var name: String
        var isEnabled: Bool
        var isMain: Bool
        var width: Int
        var height: Int
        var pixelWidth: Int
        var refreshRate: Double
        var rotation: Int
        var brightness: Double?
    }

    var name: String
    var displays: [DisplayState]
}

@MainActor
@Observable
final class PresetStore {
    static let shared = PresetStore()
    private static let key = "presets"

    private(set) var presets: [Preset] = {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Preset].self, from: data)) ?? []
    }() {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(presets), forKey: Self.key) }
    }

    /// Saves a preset. A preset with the same name is replaced.
    func save(_ preset: Preset) {
        presets = presets.filter { $0.name != preset.name } + [preset]
    }

    func delete(named name: String) {
        presets = presets.filter { $0.name != name }
    }
}

extension DisplayManager {
    /// The current setup of all known displays. A display that is off keeps the mode it had when it was on.
    func currentPreset(named name: String) -> Preset {
        let old = PresetStore.shared.presets.flatMap(\.displays)
        return Preset(name: name, displays: displays.compactMap { display in
            guard display.isEnabled, let mode = DisplayModes.current(display.id) else {
                // Off: use the last saved mode of this display, so turning it on again restores it.
                guard var state = old.last(where: { $0.key == display.stableKey }) else { return nil }
                state.isEnabled = false
                state.isMain = false
                return state
            }
            return .init(
                key: display.stableKey, name: display.name, isEnabled: true, isMain: DisplayArrangement.isMain(display.id),
                width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth, refreshRate: mode.refreshRate,
                rotation: DisplayArrangement.rotation(display.id), brightness: display.brightness
            )
        })
    }

    /// True when the displays match the preset now. Brightness and names do not count.
    func matches(_ preset: Preset) -> Bool {
        let current = currentPreset(named: "")
        return preset.displays.allSatisfy { state in
            current.displays.contains { now in
                var a = now, b = state
                a.name = ""; b.name = ""; a.brightness = nil; b.brightness = nil
                return a == b
            }
        }
    }

    /// Applies a preset. Displays that are not in the preset stay as they are.
    func apply(_ preset: Preset) {
        guard let configure = PrivateAPI.configureDisplayEnabled else { return }
        var targets: [(id: CGDirectDisplayID, state: Preset.DisplayState)] = []
        for state in preset.displays {
            if let display = displays.first(where: { $0.stableKey == state.key }) {
                targets.append((display.id, state))
            }
        }
        guard targets.contains(where: { $0.state.isEnabled }) else {
            lastError = "This preset turns off all displays."
            return
        }
        // After the preset, a physical display must be on (a virtual display does not count, see `DisplayPolicy`).
        let turnsOn = Set(targets.filter(\.state.isEnabled).map(\.id))
        let after = states.map { state in
            var state = state
            if turnsOn.contains(state.id) { state.isActive = true }
            return state
        }
        let turnsOff = Set(targets.filter { !$0.state.isEnabled }.map(\.id))
        let allowed = DisplayPolicy.canDisable(turnsOff, in: after)
        Self.log.notice("""
            Preset \(preset.name, privacy: .public): turns off \(turnsOff.sorted(), privacy: .public), \
            \(allowed ? "allowed" : "refused", privacy: .public); after: \(Self.describe(after), privacy: .public)
            """)
        guard allowed else {
            lastError = "This preset turns off all displays."
            return
        }
        lastError = nil
        let steps = targets

        configQueue.async {
            var errors: [String] = []
            // Turn displays on first, so there is always a display that is on.
            for (id, state) in steps where state.isEnabled && CGDisplayIsActive(id) == 0 {
                if let error = Self.applyEnabled(id, true, name: state.name, configure: configure) { errors.append(error) }
            }
            for (id, state) in steps where state.isEnabled {
                let current = DisplayModes.current(id)
                let same = current.map {
                    $0.width == state.width && $0.height == state.height && $0.pixelWidth == state.pixelWidth
                        && abs($0.refreshRate - state.refreshRate) < 0.01
                } ?? false
                if !same, let mode = DisplayModes.find(id, width: state.width, height: state.height,
                                                       pixelWidth: state.pixelWidth, refreshRate: state.refreshRate) {
                    if let error = DisplayModes.apply(mode, to: id) { errors.append(error) }
                }
                if DisplayArrangement.rotation(id) != state.rotation, let error = DisplayArrangement.setRotation(state.rotation, for: id) {
                    errors.append(error)
                }
            }
            if let main = steps.first(where: { $0.state.isEnabled && $0.state.isMain }), !DisplayArrangement.isMain(main.id) {
                if let error = DisplayArrangement.setMain(main.id) { errors.append(error) }
            }
            var turnedOff: Set<CGDirectDisplayID> = []
            for (id, state) in steps where !state.isEnabled && CGDisplayIsActive(id) != 0 {
                // Check again with the displays as they are now: a display may have failed to turn on.
                let live = Self.liveStates(disabled: [])
                guard DisplayPolicy.canDisable([id], in: live) else {
                    Self.log.notice("Preset: \(id, privacy: .public) stays on; displays: \(Self.describe(live), privacy: .public)")
                    errors.append("\(state.name) stays on: no other display is on.")
                    continue
                }
                if let error = Self.applyEnabled(id, false, name: state.name, configure: configure) {
                    errors.append(error)
                } else {
                    turnedOff.insert(id)
                }
            }

            let off = turnedOff
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    var disabled = self.disabled
                    for (id, state) in steps where state.isEnabled || off.contains(id) {
                        disabled[id] = state.isEnabled ? nil : state.name
                    }
                    self.disabled = disabled
                    self.lastError = errors.first
                    self.refresh()
                    // Brightness last: a display that just turned on needs a moment before it accepts DDC.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        MainActor.assumeIsolated {
                            self.refresh()
                            // Synced displays last: their shared brightness also sets the built-in display.
                            let displays = steps.filter(\.1.isEnabled).compactMap { id, state in
                                self.displays.first { $0.id == id }.map { ($0, state) }
                            }
                            for (display, state) in displays.sorted(by: { !self.isSynced($0.0) && self.isSynced($1.0) }) {
                                guard let brightness = state.brightness else { continue }
                                self.setBrightness(display, to: brightness)
                            }
                        }
                    }
                }
            }
        }
    }
}

import AppKit
import CoreGraphics
import DisplayPolicy
import Observation

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
    /// The displays as `PresetPolicy` needs them. Mode, main display and rotation are read only for a display that
    /// is on: macOS does not report them for a display that is off.
    private var presetDisplays: [PresetPolicy.Display] {
        displays.map { display in
            let on = display.isEnabled
            return PresetPolicy.Display(
                id: display.id, key: display.knownKey, name: display.name, isEnabled: on,
                mode: on ? DisplayModes.current(display.id).map {
                    .init(width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, refreshRate: $0.refreshRate)
                } : nil,
                isMain: on && DisplayArrangement.isMain(display.id), rotation: on ? DisplayArrangement.rotation(display.id) : 0,
                brightness: display.brightness
            )
        }
    }

    /// The current setup of all known displays. A display that is off is saved as off.
    func currentPreset(named name: String) -> Preset {
        PresetPolicy.current(named: name, displays: presetDisplays)
    }

    /// True when the displays match the preset now. Brightness and names do not count.
    func matches(_ preset: Preset) -> Bool {
        PresetPolicy.matches(preset, displays: presetDisplays)
    }

    /// Applies a preset. Displays that are not in the preset stay as they are.
    func apply(_ preset: Preset) {
        guard let configure = PrivateAPI.configureDisplayEnabled else { return }
        let targets = PresetPolicy.targets(of: preset, displays: presetDisplays)
        guard targets.contains(where: { $0.state.isEnabled }) else {
            lastError = "This preset turns off all displays."
            return
        }
        // After the preset, a physical display must be on (a virtual display does not count, see `DisplayPolicy`).
        let changes = PresetPolicy.changes(targets)
        let turnsOn = changes.turnsOn, turnsOff = changes.turnsOff
        let after = states.map { state in
            var state = state
            if turnsOn.contains(state.id) { state.isActive = true }
            return state
        }
        let allowed = DisplayPolicy.canDisable(turnsOff, in: after)
        Self.log.notice("""
            Preset \(preset.name, privacy: .private): turns off \(turnsOff.sorted(), privacy: .public), \
            \(allowed ? "allowed" : "refused", privacy: .public); after: \(Self.describe(after), privacy: .public)
            """)
        guard allowed else {
            lastError = "This preset turns off all displays."
            return
        }
        lastError = nil
        let steps = targets
        let builtins = builtinIDs

        configQueue.async {
            var errors: [String] = []
            // Turn displays on first, so there is always a display that is on.
            // From the list: CGDisplayIsActive returns -1 for a display that is off (see `DisplayPolicy.states`).
            for (id, state) in steps where state.isEnabled && !Self.activeDisplays().contains(id) {
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
            for (id, state) in steps where turnsOff.contains(id) && Self.activeDisplays().contains(id) {
                // Check again with the displays as they are now: a display may have failed to turn on.
                let live = Self.liveStates(disabled: [], builtins: builtins)
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
                    // Only mark the displays that really turned off. `refresh` clears the ones that are on again, so
                    // a display the preset could not turn on stays marked as off.
                    var disabled = self.disabled
                    for (id, state) in steps where off.contains(id) {
                        disabled[id] = state.name
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

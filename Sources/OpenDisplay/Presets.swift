import AppKit
import CoreGraphics
import DisplayPolicy
import Observation
import os

@MainActor
@Observable
final class PresetStore {
    static let shared = PresetStore()
    private static let key = "presets"

    private(set) var presets: [Preset] = {
        let (presets, backupKey) = StoredJSON.load([Preset].self, forKey: key)
        if let backupKey {
            DisplayManager.log.error("The saved presets could not be read. They are kept under \(backupKey, privacy: .public).")
        }
        return presets ?? []
    }() {
        didSet { StoredJSON.save(presets, forKey: Self.key) }
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
    /// The displays as `PresetPolicy` needs them. Mode, main display and rotation are from the last refresh, and only
    /// for a display that is on: macOS does not report them for a display that is off.
    private var presetDisplays: [PresetPolicy.Display] {
        displays.map { display in
            let on = display.isEnabled
            return PresetPolicy.Display(
                id: display.id, key: display.knownKey, name: display.name, isEnabled: on,
                mode: on ? display.mode.map {
                    .init(width: $0.width, height: $0.height, pixelWidth: $0.pixelWidth, refreshRate: $0.refreshRate)
                } : nil,
                isMain: on && display.isMain, rotation: on ? display.rotation : 0,
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

    /// Applies a preset. Displays that are not in the preset stay as they are. `done` gets the message for the user
    /// (why nothing changed, what was skipped, what failed), or `nil` when the whole preset applied. The menu shows
    /// the same message, until the next preset replaces it.
    func apply(_ preset: Preset, done: @escaping @MainActor (String?) -> Void = { _ in }) {
        let finish: @MainActor (String?) -> Void = { message in
            self.errors[.preset] = message
            done(message)
        }
        guard let configure = PrivateAPI.configureDisplayEnabled else {
            return finish("This macOS version does not support turning displays off.")
        }
        let plan = PresetPolicy.plan(preset, displays: presetDisplays)
        if let refusal = plan.refusal {
            return finish(refusal)
        }
        let targets = plan.targets
        // After the preset, a physical display must be on (a virtual display does not count, see `DisplayPolicy`).
        let onOff = PresetPolicy.changes(targets)
        let turnsOn = onOff.turnsOn, turnsOff = onOff.turnsOff
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
            return finish(PresetPolicy.turnsOffAllDisplays(notConnected: plan.notConnected))
        }
        errors.startPreset(changing: targets.map { $0.id })
        let steps = targets
        let builtins = builtinIDs
        let skipped = plan.skipped
        // Show the displays that turn off as off at once, as `setEnabled` does: the menu's turn-off check and the
        // brightness sync then see their new state. They stay in the list while the preset runs (see
        // `DisplayChanges.listed`). Only the displays that are on now: the preset leaves the others alone.
        let started = displays.filter { turnsOff.contains($0.id) && $0.isEnabled }.map { display in
            display.isEnabled = false
            return changes.begin(display.id)
        }

        configQueue.async {
            // One error per display: its first failure (a display that did not turn on also fails its later steps).
            // Turn displays on first, so there is always a display that is on. A display that macOS accepts but that
            // is not on after (it is unplugged, or the lid is closed) fails, and keeps its off mark.
            // From the list: CGDisplayIsActive returns -1 for a display that is off (see `DisplayPolicy.states`).
            var results = PresetPolicy.turnOn(
                steps, builtins: builtins,
                turnOn: { Self.applyEnabled($0, true, name: $1, configure: configure) },
                isActive: { Self.activeDisplays().contains($0) })
            // A display that did not turn on has no modes or rotation to set: its error already says why.
            for (id, state) in steps where state.isEnabled && !results.failed(id) {
                let current = DisplayModes.current(id)
                let same = current.map {
                    $0.width == state.width && $0.height == state.height && $0.pixelWidth == state.pixelWidth
                        && abs($0.refreshRate - state.refreshRate) < 0.01
                } ?? false
                if !same {
                    if let mode = DisplayModes.find(id, width: state.width, height: state.height,
                                                    pixelWidth: state.pixelWidth, refreshRate: state.refreshRate) {
                        results.record(id, error: DisplayModes.apply(mode, to: id))
                    } else {
                        results.record(id, error: PresetPolicy.resolutionNotAvailable(state))
                    }
                }
                if DisplayArrangement.rotation(id) != state.rotation {
                    results.record(id, error: DisplayArrangement.setRotation(state.rotation, for: id))
                }
            }
            if let main = steps.first(where: { $0.state.isEnabled && $0.state.isMain }), !DisplayArrangement.isMain(main.id) {
                results.record(main.id, error: DisplayArrangement.setMain(main.id))
            }
            var turnedOff: Set<CGDirectDisplayID> = []
            for (id, state) in steps where turnsOff.contains(id) && Self.activeDisplays().contains(id) {
                // Check again with the displays as they are now: a display may have failed to turn on.
                let live = Self.liveStates(disabled: [], builtins: builtins)
                guard DisplayPolicy.canDisable([id], in: live) else {
                    Self.log.notice("Preset: \(id, privacy: .public) stays on; displays: \(Self.describe(live), privacy: .public)")
                    results.record(id, error: "\(state.name) stays on: no other display is on.")
                    continue
                }
                if let error = Self.applyEnabled(id, false, name: state.name, configure: configure) {
                    results.record(id, error: error)
                } else {
                    turnedOff.insert(id)
                }
            }

            let off = turnedOff
            let report = PresetPolicy.report(skipped: skipped, results: results)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    for change in started { _ = self.changes.end(change) }
                    // Only mark the displays that really turned off. `refresh` clears the ones that are on again, so
                    // a display the preset could not turn on stays marked as off.
                    var marks = self.offMarks
                    for (id, state) in steps where off.contains(id) {
                        marks.markOff(id, name: state.name, session: Self.loginSession)
                    }
                    self.offMarks = marks
                    finish(report)
                    self.refresh()
                    // Brightness last: a display that just turned on needs a moment before it accepts DDC.
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.ddcReadyDelay) {
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

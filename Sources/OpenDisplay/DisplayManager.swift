import AppKit
import CoreGraphics
import DisplayPolicy
import Observation

@MainActor
@Observable
final class Display: Identifiable {
    let id: CGDirectDisplayID
    var name: String
    let isBuiltin: Bool
    /// Not a real screen, such as the placeholder that macOS makes when no display is on (see `DisplayPolicy`).
    let isVirtual: Bool
    var isEnabled = true
    /// 0...1, the position of the brightness slider. `nil` while we do not know the value yet.
    /// The lowest part of the range dims the image in software (see `DisplayManager.setBrightness`).
    var brightness: Double?
    var brightnessError: String?
    /// 0...1. `nil` while we do not know the value yet.
    var volume: Double?
    var isMuted = false
    /// True after the first volume read over DDC works. It stays true while the display is off,
    /// so the menu keeps the same items.
    var supportsVolume = false

    @ObservationIgnored var ddc: DDCService?
    @ObservationIgnored var ddcMax: UInt16 = 100
    @ObservationIgnored var volumeMax: UInt16 = 100
    /// Software dimming: 1 is the normal image.
    @ObservationIgnored var dimming: Double = 1
    /// How the light follows the DDC level. From the calibration of the display model, if there is one.
    @ObservationIgnored var curve = ExternalCurve()
    /// The monitor settings that change the light, by name (see `BrightnessCalibration.monitorSettings`).
    /// `nil` until read.
    var monitorSettings: [String: UInt16]?

    /// The VCP codes the external display supports, with their allowed values (see `VCP.parse`). `nil` until read.
    var capabilities: [UInt8: [UInt8]]?
    /// 0...1. `nil` while we do not know the value yet.
    var contrast: Double?
    @ObservationIgnored var contrastMax: UInt16 = 100
    var colorPreset: UInt8?
    var input: UInt8?

    init(id: CGDirectDisplayID, name: String) {
        self.id = id
        self.name = name
        self.isBuiltin = CGDisplayIsBuiltin(id) != 0
        self.isVirtual = DisplayPolicy.isVirtual(
            vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), isBuiltin: isBuiltin)
    }

    /// Identifies the external display across reconnects and restarts (the display ID can change).
    var stableKey: String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// Identifies the display model, so all displays of one model share a calibration.
    var modelKey: String {
        BrightnessCalibration.key(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id))
    }

    /// True if the backlight itself can change. Without it, the slider only dims in software.
    var hasHardwareBrightness: Bool {
        isBuiltin ? PrivateAPI.setBrightness != nil : ddc != nil
    }

    var brightnessControl: BrightnessControl {
        guard hasHardwareBrightness else { return .software(scale: curve.scale) }
        return isBuiltin ? .builtin : .external(curve)
    }
}

@MainActor
@Observable
final class DisplayManager {
    private(set) var displays: [Display] = []
    var lastError: String?
    /// Goes up after each refresh. Rows that show state macOS does not report changes for
    /// (display modes, main display, rotation) read it, so they update after a change.
    private(set) var revision = 0

    @ObservationIgnored private var byID: [CGDirectDisplayID: Display] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var wakeObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingRefresh: DispatchWorkItem?

    /// Displays we turned off, with their names. Kept so they stay in the list (and survive an app restart).
    @ObservationIgnored var disabled: [CGDirectDisplayID: String] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: "disabledDisplays") as? [String: String] ?? [:]
            return Dictionary(uniqueKeysWithValues: stored.compactMap { key, name in UInt32(key).map { ($0, name) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0), $1) }), forKey: "disabledDisplays")
        }
    }

    init() {
        refresh()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            // macOS also does this when the app quits, but do not depend on it.
            MainActor.assumeIsolated { SoftwareDimming.restoreAll() }
        }
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        // After sleep, a display may have gone away (see `keepADisplayOn`).
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
    }

    /// Screen changes arrive in bursts, so wait for them to settle.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func refresh() {
        var online = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(UInt32(online.count), &online, &count)
        online = Array(online.prefix(Int(count)))

        var disabled = self.disabled
        // A display that is active again (for example after a reboot or replug) is no longer "off".
        for id in online where CGDisplayIsActive(id) != 0 {
            disabled[id] = nil
        }
        self.disabled = disabled

        var ids = online.filter { CGDisplayIsActive($0) != 0 || disabled[$0] != nil }
        ids += disabled.keys.filter { !ids.contains($0) }

        let ddc = DDCDiscovery.services(for: ids.filter { CGDisplayIsActive($0) != 0 })

        var next: [Display] = []
        for id in ids {
            let display = byID[id] ?? Display(id: id, name: disabled[id] ?? Self.name(of: id))
            if changing.contains(id) {
                next.append(display)
                continue
            }
            display.isEnabled = CGDisplayIsActive(id) != 0
            if display.isEnabled {
                display.name = Self.name(of: id)
                if display.ddc == nil || ddc[id] == nil {
                    display.ddc = ddc[id]
                    display.brightness = nil
                    display.volume = nil
                }
            } else {
                display.ddc = nil
            }
            next.append(display)
        }
        byID = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        displays = next.sorted { ($0.isBuiltin ? 1 : 0, $0.id) < ($1.isBuiltin ? 1 : 0, $1.id) }
        // After the DDC check: a display with DDC and one without use different calibrations.
        updateCurves()

        for display in displays where display.isEnabled && display.dimming < 1 {
            // A display that turned off and on again has its normal color table again.
            SoftwareDimming.set(display.dimming, for: display.id)
        }
        for display in displays where display.isEnabled && display.brightness == nil {
            readBrightness(display)
        }
        for display in displays where display.isEnabled && display.ddc != nil && display.volume == nil {
            readVolume(display)
        }
        for display in displays where display.isEnabled && display.ddc != nil && display.capabilities == nil {
            readCapabilities(display)
        }
        observeBuiltinBrightness()
        syncFromBuiltin()
        XDRBoost.shared.displaysChanged()
        revision += 1
        keepADisplayOn()
    }

    // MARK: Brightness

    // All brightness sliders follow the macOS curve (see `BrightnessCurve`), so the same slider position gives
    // about the same light on each display. Below an external display's lowest level, software dimming makes it darker.

    func readBrightness(_ display: Display) {
        display.brightnessError = nil
        if display.isBuiltin {
            var value: Float = 0
            if let get = PrivateAPI.getBrightness, get(display.id, &value) == 0 {
                display.brightness = BrightnessControl.builtin.slider(level: Double(value), dimming: display.dimming)
            } else {
                display.brightness = display.brightnessControl.slider(level: nil, dimming: display.dimming)
            }
            return
        }
        guard let ddc = display.ddc else {
            // No DDC: the slider still works, with software dimming only.
            display.brightness = display.brightnessControl.slider(level: nil, dimming: display.dimming)
            return
        }
        ddc.readLater(vcp: VCP.brightness) { [weak display] result in
            MainActor.assumeIsolated {
                guard let display else { return }
                if let result, result.max > 0 {
                    display.ddcMax = result.max
                    let level = Double(result.current) / Double(result.max)
                    display.brightness = BrightnessControl.external(display.curve).slider(level: level, dimming: display.dimming)
                } else {
                    // Writes often work when reads do not, so still allow control.
                    display.brightness = 0.5
                    display.brightnessError = "Could not read value over DDC"
                }
            }
        }
    }

    func setBrightness(_ display: Display, to value: Double) {
        let value = min(max(value, 0), 1)
        if display.isBuiltin {
            applyBrightness(display, value)
            followBuiltin(value)
        } else if isSynced(display) {
            setSharedBrightness(value)
        } else {
            applyBrightness(display, value)
        }
    }

    /// Sets one display, without sync.
    private func applyBrightness(_ display: Display, _ value: Double) {
        display.brightness = value
        let (level, dimming) = display.brightnessControl.split(value)
        display.dimming = dimming
        SoftwareDimming.set(dimming, for: display.id)
        guard let level else { return }
        if display.isBuiltin {
            lastBuiltinBacklight = Float(level)
            _ = PrivateAPI.setBrightness?(display.id, Float(level))
        } else {
            display.ddc?.setLater(vcp: VCP.brightness, value: UInt16((level * Double(display.ddcMax)).rounded()))
        }
    }

    // MARK: Brightness sync

    // An external display can follow the built-in display's brightness, so the brightness keys and automatic brightness
    // (light sensor) also work for it. macOS tells us when the built-in brightness changes, with its new target
    // value, before its fade starts. So the external display changes at the same time as the built-in display.

    @ObservationIgnored private var lastBuiltinBacklight: Float?
    /// Displays we get brightness notifications for. macOS has no tested way to stop them, so register each once.
    @ObservationIgnored private var observedBuiltins: Set<CGDirectDisplayID> = []

    private var syncedKeys = Set(UserDefaults.standard.stringArray(forKey: "syncedDisplays") ?? []) {
        didSet { UserDefaults.standard.set(syncedKeys.sorted(), forKey: "syncedDisplays") }
    }

    func isSynced(_ display: Display) -> Bool {
        !display.isBuiltin && syncedKeys.contains(display.stableKey)
    }

    // Synced displays share one brightness: a slider position on the macOS curve, from black up to the maximum light
    // of the brightest display. Where both can give the light, the built-in and the synced displays give the same
    // light. Above the maximum of a display, it stays at its maximum, and the brighter displays go on.

    /// The slider position of the synced displays. `nil` until the first sync.
    @ObservationIgnored private(set) var sharedBrightness: Double?

    private var builtin: Display? {
        displays.first { $0.isBuiltin && $0.isEnabled }
    }

    private var syncedDisplays: [Display] {
        displays.filter { $0.isEnabled && isSynced($0) }
    }

    /// The maximum light of the brightest synced display, as a part of the built-in display's maximum. At least 1.
    private var sharedMaximum: Double {
        max(syncedDisplays.compactMap { calibrationInUse(for: $0)?.maximum }.max() ?? 1, 1)
    }

    /// The built-in display's slider position for a shared slider position: the same light, up to its maximum.
    private func builtinSlider(shared: Double) -> Double {
        BrightnessCurve.slider(light: min(BrightnessCurve.light(slider: shared) * sharedMaximum, 1))
    }

    /// The inverse of `builtinSlider(shared:)`, for a built-in display below its maximum.
    private func sharedSlider(builtin: Double) -> Double {
        BrightnessCurve.slider(light: BrightnessCurve.light(slider: builtin) / sharedMaximum)
    }

    func setSharedBrightness(_ value: Double) {
        let value = min(max(value, 0), 1)
        sharedBrightness = value
        for display in syncedDisplays {
            applyBrightness(display, value)
        }
        if let builtin {
            applyBrightness(builtin, builtinSlider(shared: value))
        }
    }

    /// The synced displays follow a change of the built-in display (keys, light sensor, slider).
    private func followBuiltin(_ value: Double) {
        // At its maximum, the built-in display cannot show a shared brightness above it. So keep that brightness.
        let aboveBuiltin = value >= 1 && (sharedBrightness ?? 0) >= sharedSlider(builtin: 1)
        if !aboveBuiltin {
            sharedBrightness = sharedSlider(builtin: value)
        }
        guard let shared = sharedBrightness else { return }
        for display in syncedDisplays {
            applyBrightness(display, shared)
        }
    }

    /// True if a brightness key must change the shared brightness here, because macOS cannot: up with the built-in
    /// display at its maximum, or down from above its maximum.
    func keyChangesSharedBrightness(up: Bool) -> Bool {
        guard sharedMaximum > 1, !syncedDisplays.isEmpty, let shared = sharedBrightness,
              let builtinValue = builtin?.brightness else { return false }
        return up ? builtinValue >= 1 && shared < 1 : shared > sharedSlider(builtin: 1) + 1e-6
    }

    func setSynced(_ display: Display, _ synced: Bool) {
        var keys = syncedKeys
        if synced { keys.insert(display.stableKey) } else { keys.remove(display.stableKey) }
        syncedKeys = keys
        updateCurves()
        if !synced, let brightness = display.brightness {
            // The same slider position gives a different light without sync.
            setBrightness(display, to: brightness)
        }
        lastBuiltinBacklight = nil
        syncFromBuiltin()
    }

    /// Call after the displays change. Also keeps the built-in slider up to date when the keys change it.
    private func observeBuiltinBrightness() {
        guard let builtin = displays.first(where: \.isBuiltin), !observedBuiltins.contains(builtin.id),
              let register = PrivateAPI.registerForBrightnessChanges else { return }
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let result = register(builtin.id, observer) { _, observer, _, _, info in
            guard let observer else { return }
            // The value comes as a number or as a string, depending on the macOS version.
            let value = (info as NSDictionary?)?["value"].map { Float(($0 as AnyObject).doubleValue) }
            // An address, because a pointer cannot go to another thread.
            let address = Int(bitPattern: observer)
            let deliver: @Sendable () -> Void = {
                MainActor.assumeIsolated {
                    let observer = UnsafeRawPointer(bitPattern: address)!
                    Unmanaged<DisplayManager>.fromOpaque(observer).takeUnretainedValue().syncFromBuiltin(value)
                }
            }
            if Thread.isMainThread { deliver() } else { DispatchQueue.main.async(execute: deliver) }
        }
        if result == 0 { observedBuiltins.insert(builtin.id) }
    }

    /// - Parameter notified: The new built-in brightness from the notification, or nil to read it.
    private func syncFromBuiltin(_ notified: Float? = nil) {
        // The calibration sets the built-in brightness itself, and the external display must not follow it.
        guard !isCalibrating else { return }
        guard let builtin = displays.first(where: { $0.isBuiltin && $0.isEnabled }) else { return }
        var backlight: Float = 0
        if let notified {
            backlight = notified
        } else {
            guard let get = PrivateAPI.getBrightness, get(builtin.id, &backlight) == 0 else { return }
        }
        guard backlight != lastBuiltinBacklight else { return }
        lastBuiltinBacklight = backlight
        let value = BrightnessControl.builtin.slider(level: Double(backlight), dimming: builtin.dimming)
        builtin.brightness = value
        followBuiltin(value)
    }

    // MARK: Calibration

    private(set) var calibrations = CalibrationStore.load() {
        didSet { CalibrationStore.save(calibrations) }
    }

    /// True while the calibration window controls the brightness. Then brightness sync stops.
    @ObservationIgnored var isCalibrating = false

    func calibration(for display: Display) -> BrightnessCalibration? {
        calibrations[display.modelKey]
    }

    func setCalibration(_ calibration: BrightnessCalibration?, for display: Display) {
        calibrations[display.modelKey] = calibration
        updateCurves()
        for other in displays where other.modelKey == display.modelKey && !isSynced(other) {
            if let brightness = other.brightness, other.isEnabled {
                setBrightness(other, to: brightness)
            }
        }
        lastBuiltinBacklight = nil
        syncFromBuiltin()
    }

    /// A calibration with DDC is only for a display with DDC, and one without DDC only for a display without it.
    private func calibrationInUse(for display: Display) -> BrightnessCalibration? {
        calibrations[display.modelKey].flatMap { $0.usesDDC == (display.ddc != nil) ? $0 : nil }
    }

    /// Call after a change of the displays, the calibrations, or the sync: the brightest synced display sets the
    /// range of all synced displays.
    private func updateCurves() {
        let shared = sharedMaximum
        for display in displays {
            let calibration = calibrationInUse(for: display)
            var curve = calibration?.curve ?? ExternalCurve()
            if isSynced(display) {
                curve.scale = shared / (calibration?.maximum ?? 1)
            }
            display.curve = curve
        }
    }

    /// Reads the monitor settings that change the light, into `monitorSettings`.
    func readMonitorSettings(_ display: Display) {
        guard let ddc = display.ddc else { return }
        for setting in BrightnessCalibration.monitorSettings
        where display.capabilities?.isEmpty != false || display.capabilities?[setting.vcp] != nil {
            ddc.readLater(vcp: setting.vcp) { [weak display] result in
                MainActor.assumeIsolated {
                    guard let display, let result else { return }
                    display.monitorSettings = (display.monitorSettings ?? [:]).merging([setting.name: result.current]) { $1 }
                }
            }
        }
    }

    // MARK: Volume

    /// External display speakers only: macOS cannot change their volume, but most external displays accept it over DDC.
    func readVolume(_ display: Display) {
        guard let ddc = display.ddc else { return }
        ddc.readLater(vcp: VCP.volume) { [weak display] result in
            MainActor.assumeIsolated {
                guard let display, let result, result.max > 0 else { return }
                display.volumeMax = result.max
                display.volume = Double(result.current) / Double(result.max)
                display.supportsVolume = true
            }
        }
        ddc.readLater(vcp: VCP.mute) { [weak display] result in
            MainActor.assumeIsolated {
                guard let display, let result else { return }
                display.isMuted = result.current == 1
            }
        }
    }

    func setVolume(_ display: Display, to value: Double) {
        let value = min(max(value, 0), 1)
        display.volume = value
        display.ddc?.setLater(vcp: VCP.volume, value: UInt16((value * Double(display.volumeMax)).rounded()))
        // Like the system volume: moving the slider ends mute.
        if display.isMuted {
            setMuted(display, false)
        }
    }

    func setMuted(_ display: Display, _ muted: Bool) {
        display.isMuted = muted
        display.ddc?.setLater(vcp: VCP.mute, value: muted ? 1 : 2)
    }

    // MARK: On/off

    /// Displays with an on/off change in progress. `refresh` must not undo their new state.
    @ObservationIgnored private var changing: Set<CGDirectDisplayID> = []
    @ObservationIgnored let configQueue = DispatchQueue(label: "dev.m9t.OpenDisplay.display-config")

    /// Shows the new state immediately, then applies it after the menu animation.
    /// Applying blocks until macOS has changed the display setup, so it runs off the main thread.
    func setEnabled(_ display: Display, _ enabled: Bool) {
        lastError = nil
        guard let configure = PrivateAPI.configureDisplayEnabled else {
            lastError = "This macOS version does not support turning displays off."
            return
        }
        if !enabled, !DisplayPolicy.canDisable([display.id], in: states) {
            lastError = "You cannot turn off the last display that is on."
            return
        }

        let id = display.id
        let name = display.name
        display.isEnabled = enabled
        changing.insert(id)

        configQueue.asyncAfter(deadline: .now() + 0.3) {
            let error = Self.applyEnabled(id, enabled, name: name, configure: configure)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.changing.remove(id)
                    if let error {
                        display.isEnabled = !enabled
                        self.lastError = error
                        return
                    }
                    var disabled = self.disabled
                    disabled[id] = enabled ? nil : name
                    self.disabled = disabled
                    self.scheduleRefresh()
                }
            }
        }
    }

    /// The displays in the list, for `DisplayPolicy`. A display with a change in progress has its new state.
    var states: [DisplayState] {
        let disabled = self.disabled
        return displays.map {
            DisplayState(id: $0.id, isBuiltin: $0.isBuiltin, isOnline: CGDisplayIsOnline($0.id) != 0,
                         isActive: $0.isEnabled, isVirtual: $0.isVirtual, isDisabledByUs: disabled[$0.id] != nil)
        }
    }

    /// The displays as macOS reports them now, for `DisplayPolicy`: the online and active ones, and `disabled`
    /// (displays we turned off), which may not be online. Safe on any thread.
    nonisolated static func liveStates(disabled: Set<CGDirectDisplayID>) -> [DisplayState] {
        func list(_ get: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError)
            -> [CGDirectDisplayID] {
            var ids = [CGDirectDisplayID](repeating: 0, count: 16)
            var count: UInt32 = 0
            guard get(UInt32(ids.count), &ids, &count) == .success else { return [] }
            return Array(ids.prefix(Int(count)))
        }
        var ids = list(CGGetOnlineDisplayList)
        ids += list(CGGetActiveDisplayList).filter { !ids.contains($0) }
        ids += disabled.sorted().filter { !ids.contains($0) }
        return ids.map { id in
            let builtin = CGDisplayIsBuiltin(id) != 0
            return DisplayState(
                id: id, isBuiltin: builtin, isOnline: CGDisplayIsOnline(id) != 0, isActive: CGDisplayIsActive(id) != 0,
                isVirtual: DisplayPolicy.isVirtual(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id),
                                                   isBuiltin: builtin),
                isDisabledByUs: disabled.contains(id))
        }
    }

    @ObservationIgnored private var isRestoring = false

    /// When the last physical display that is on goes away (for example, the TV is unplugged while OpenDisplay has
    /// the built-in display off), macOS does not turn another display on: it shows a virtual placeholder display, and
    /// the Mac has no screen. Then turn on a display that OpenDisplay turned off, the built-in display first.
    /// `refresh` calls this: at launch, after each change of the displays, and after wake.
    private func keepADisplayOn() {
        guard let configure = PrivateAPI.configureDisplayEnabled, changing.isEmpty, !isRestoring else { return }
        let disabled = self.disabled
        guard !DisplayPolicy.displaysToRestore(in: Self.liveStates(disabled: Set(disabled.keys))).isEmpty else { return }
        isRestoring = true
        // Wait a moment: after wake, a display can take a few seconds to come back on by itself.
        configQueue.asyncAfter(deadline: .now() + 2) {
            // Check again: the displays may have changed, also by a toggle or a preset before this in the queue.
            let candidates = DisplayPolicy.displaysToRestore(in: Self.liveStates(disabled: Set(disabled.keys)))
            var restored: CGDirectDisplayID?
            var errors: [String] = []
            for id in candidates {
                if let error = Self.applyEnabled(id, true, name: disabled[id] ?? "Display \(id)", configure: configure) {
                    errors.append(error)
                } else {
                    restored = id
                    break
                }
            }
            let error = errors.first
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isRestoring = false
                    guard let restored else {
                        // No new refresh: it would only try again, and fail again.
                        if let error { self.lastError = error }
                        return
                    }
                    var disabled = self.disabled
                    disabled[restored] = nil
                    self.disabled = disabled
                    self.byID[restored]?.isEnabled = true
                    self.scheduleRefresh()
                }
            }
        }
    }

    /// Returns an error message, or nil on success.
    nonisolated static func applyEnabled(
        _ id: CGDirectDisplayID, _ enabled: Bool, name: String, configure: PrivateAPI.ConfigureDisplayEnabled
    ) -> String? {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return "Could not start display configuration."
        }
        let result = configure(config, id, enabled)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            return "Could not turn \(enabled ? "on" : "off") \(name) (error \(result.rawValue))."
        }
        // Session only: a logout or reboot turns every display on again, so you cannot lock yourself out.
        let completed = CGCompleteDisplayConfiguration(config, .forSession)
        guard completed == .success else {
            return "Could not apply display configuration (error \(completed.rawValue))."
        }
        return nil
    }

    // MARK: Display modes

    /// Changes the resolution or refresh rate. Applying blocks until macOS has changed the display, so it runs off the main thread.
    func setMode(_ display: Display, _ mode: CGDisplayMode) {
        let id = display.id
        // A display mode cannot change after macOS creates it, so it is safe to use on another thread.
        nonisolated(unsafe) let mode = mode
        applyInBackground { DisplayModes.apply(mode, to: id) }
    }

    /// Runs a display change off the main thread (it blocks until macOS has changed the display),
    /// then shows its error, if any, and reads the displays again.
    private func applyInBackground(_ change: @escaping @Sendable () -> String?) {
        lastError = nil
        configQueue.async {
            let error = change()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let error { self.lastError = error }
                    self.scheduleRefresh()
                }
            }
        }
    }

    // MARK: Arrangement

    func setMain(_ display: Display) {
        let id = display.id
        applyInBackground { DisplayArrangement.setMain(id) }
    }

    func setRotation(_ display: Display, _ degrees: Int) {
        let id = display.id
        applyInBackground { DisplayArrangement.setRotation(degrees, for: id) }
    }

    // MARK: External display settings (DDC)

    private func readCapabilities(_ display: Display) {
        // Empty while reading, so a refresh does not start a second read. Nil after a failed read, so the next refresh tries again.
        display.capabilities = [:]
        display.ddc?.capabilitiesLater { [weak display] text in
            MainActor.assumeIsolated {
                display?.capabilities = text.map(VCP.parse(capabilities:))
            }
        }
    }

    /// Reads the values in the Options submenu. The menu calls this when it opens, so they are ready in time.
    func readDDCSettings(_ display: Display) {
        guard let ddc = display.ddc, let capabilities = display.capabilities else { return }
        if capabilities[VCP.contrast] != nil {
            ddc.readLater(vcp: VCP.contrast) { [weak display] result in
                MainActor.assumeIsolated {
                    guard let display, let result, result.max > 0 else { return }
                    display.contrastMax = result.max
                    display.contrast = Double(result.current) / Double(result.max)
                }
            }
        }
        if capabilities[VCP.colorPreset] != nil {
            ddc.readLater(vcp: VCP.colorPreset) { [weak display] result in
                MainActor.assumeIsolated { display?.colorPreset = result.map { UInt8(truncatingIfNeeded: $0.current) } }
            }
        }
        if capabilities[VCP.input] != nil {
            ddc.readLater(vcp: VCP.input) { [weak display] result in
                MainActor.assumeIsolated { display?.input = result.map { UInt8(truncatingIfNeeded: $0.current) } }
            }
        }
    }

    func setContrast(_ display: Display, to value: Double) {
        let value = min(max(value, 0), 1)
        display.contrast = value
        let level = UInt16((value * Double(display.contrastMax)).rounded())
        display.ddc?.setLater(vcp: VCP.contrast, value: level)
        display.monitorSettings?["contrast"] = level
    }

    func setColorPreset(_ display: Display, _ preset: UInt8) {
        display.colorPreset = preset
        display.ddc?.setLater(vcp: VCP.colorPreset, value: UInt16(preset))
        display.monitorSettings?["colorPreset"] = UInt16(preset)
    }

    /// Switches the external display to another input. If the Mac is not on that input, the display disconnects.
    func setInput(_ display: Display, _ input: UInt8) {
        display.input = input
        display.ddc?.setLater(vcp: VCP.input, value: UInt16(input))
    }

    // MARK: Names

    static func name(of id: CGDirectDisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? CGDirectDisplayID) == id }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display \(id)"
    }
}

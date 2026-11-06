import AppKit
import CoreGraphics
import DisplayPolicy
import Observation
import os

@MainActor
@Observable
final class Display: Identifiable {
    let id: CGDirectDisplayID
    var name: String
    /// Read again when the display is on: macOS does not know a display that is off (see `DisplayPolicy.states`).
    fileprivate(set) var isBuiltin: Bool
    /// Not a real screen, such as the placeholder that macOS makes when no display is on (see `DisplayPolicy`).
    /// Read from macOS each time, because display IDs are reused. A display that is off is not virtual: macOS has no
    /// identity for it then.
    var isVirtual: Bool {
        DisplayManager.activeDisplays().contains(id) && DisplayPolicy.isVirtual(
            vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), isBuiltin: isBuiltin)
    }
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
    /// `stableKey`, from the last time the display was on: macOS has no identity for a display that went away.
    @ObservationIgnored var stableKeyWhenOn: String?
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
        // -1 for a display macOS does not know now (see `DisplayPolicy.states`).
        self.isBuiltin = DisplayPolicy.isTrue(CGDisplayIsBuiltin(id))
    }

    /// The key of the display from when it was last on, kept by `DisplayManager`: macOS may not know a display that is
    /// off (see `DisplayKey`).
    @ObservationIgnored var rememberedKey: String?

    /// The key macOS reports for the display now, `nil` while it does not know the display.
    var reportedKey: String? {
        DisplayKey.key(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
    }

    /// Identifies the display across reconnects and restarts (the display ID can change): the remembered key, else the
    /// key macOS reports, or `nil` when there is neither (see `DisplayKey`).
    var knownKey: String? {
        DisplayKey.key(reported: reportedKey, remembered: rememberedKey)
    }

    /// Identifies the external display across reconnects and restarts (the display ID can change).
    var stableKey: String {
        knownKey ?? "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
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
    /// The software dimming of the displays that went away, for when they come back.
    @ObservationIgnored private var reconnects = ReconnectMemory()
    /// Displays the app turned on since the last refresh. The app shows them as on before the refresh, so the refresh
    /// cannot see the change in its lists.
    @ObservationIgnored private var turnedOnByApp: Set<CGDirectDisplayID> = []

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

    /// The built-in displays, remembered from when they were on: while a display is off, macOS does not say if it is
    /// built-in (see `DisplayPolicy.states`). Kept across app restarts, like `disabled`.
    @ObservationIgnored var builtinIDs: Set<CGDirectDisplayID> {
        get { Set((UserDefaults.standard.array(forKey: "builtinDisplays") as? [Int] ?? []).map { CGDirectDisplayID($0) }) }
        set { UserDefaults.standard.set(newValue.sorted().map { Int($0) }, forKey: "builtinDisplays") }
    }

    /// The key of each display, by ID, remembered from when the display was last on (see `Display.rememberedKey`). Kept
    /// across app restarts, like `disabled`.
    @ObservationIgnored var displayKeys: [CGDirectDisplayID: String] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: "displayKeys") as? [String: String] ?? [:]
            return Dictionary(uniqueKeysWithValues: stored.compactMap { id, key in UInt32(id).map { ($0, key) } })
        }
        set {
            UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: newValue.map { (String($0), $1) }), forKey: "displayKeys")
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
            Self.log.notice("Screen parameters changed")
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        // After sleep, a display may have gone away (see `keepADisplayOn`).
        let workspace = NSWorkspace.shared.notificationCenter
        wakeObservers = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].map { name in
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Self.log.notice("Wake: \(name.rawValue, privacy: .public)")
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
        // From the lists: CGDisplayIsActive returns -1 for a display macOS does not know now (see `DisplayPolicy`).
        let online = Self.onlineDisplays()
        let active = Set(Self.activeDisplays())

        var disabled = self.disabled
        // A display that is active again (for example after a reboot or replug) is no longer "off".
        for id in active {
            disabled[id] = nil
        }
        self.disabled = disabled

        let builtins = DisplayPolicy.rememberedBuiltins(
            builtinIDs, answers: Dictionary(uniqueKeysWithValues: active.map { ($0, CGDisplayIsBuiltin($0)) }))
        if builtins != builtinIDs { builtinIDs = builtins }

        let storedKeys = displayKeys
        let keys = DisplayKey.remembered(storedKeys, reported: Dictionary(uniqueKeysWithValues: active.map {
            ($0, DisplayKey.key(vendor: CGDisplayVendorNumber($0), model: CGDisplayModelNumber($0), serial: CGDisplaySerialNumber($0)))
        }), keeping: Set(online).union(disabled.keys))
        if keys != storedKeys { displayKeys = keys }

        var ids = online.filter { active.contains($0) || disabled[$0] != nil }
        ids += active.filter { !ids.contains($0) }
        ids += disabled.keys.filter { !ids.contains($0) }

        let ddc = DDCDiscovery.services(for: ids.filter { active.contains($0) })

        let before = byID.values.map { reconnectSnapshot($0) }
        var next: [Display] = []
        for id in ids {
            let display = byID[id] ?? Display(id: id, name: disabled[id] ?? Self.name(of: id))
            display.rememberedKey = keys[id]
            if changing.contains(id) {
                next.append(display)
                continue
            }
            display.isEnabled = active.contains(id)
            display.isBuiltin = DisplayPolicy.isBuiltin(answer: CGDisplayIsBuiltin(id), id: id, builtins: builtins)
            if display.isEnabled {
                display.name = Self.name(of: id)
                display.stableKeyWhenOn = display.stableKey
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
        // A display that went away and came back is a new display object, so its dimming starts at 1: it gets back
        // what it had when it went away.
        let plan = reconnects.refresh(before: before, after: next.map { reconnectSnapshot($0) },
                                      turnedOnByApp: turnedOnByApp)
        turnedOnByApp = []
        for display in next {
            if let dimming = plan.dimming[display.id] { display.dimming = dimming }
        }
        byID = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        displays = next.sorted { ($0.isBuiltin ? 1 : 0, $0.id) < ($1.isBuiltin ? 1 : 0, $1.id) }
        // After the DDC check: a display with DDC and one without use different calibrations.
        updateCurves()
        if plan.resyncsBrightness {
            // `syncFromBuiltin` below applies the shared brightness only when the built-in brightness changed.
            lastBuiltinBacklight = nil
            // A display that just turned on needs a moment before it accepts DDC, so its DDC write now may be lost.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.ddcReadyDelay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.lastBuiltinBacklight = nil
                    self.syncFromBuiltin()
                }
            }
        }

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

    /// How long a display that just turned on needs before it accepts DDC writes.
    static let ddcReadyDelay: TimeInterval = 1.5

    /// A display for `ReconnectMemory`.
    private func reconnectSnapshot(_ display: Display) -> ReconnectMemory.Snapshot {
        ReconnectMemory.Snapshot(id: display.id, key: display.stableKeyWhenOn, isEnabled: display.isEnabled,
                                 dimming: display.dimming,
                                 // From the key it had when on: macOS has no identity for a display that went away.
                                 isSynced: !display.isBuiltin && (display.stableKeyWhenOn.map { syncedKeys.contains($0) } ?? false))
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
        if !enabled {
            let states = self.states
            let allowed = DisplayPolicy.canDisable([display.id], in: states)
            Self.log.notice("""
                Turn off \(display.id, privacy: .public): \(allowed ? "allowed" : "refused", privacy: .public); \
                displays: \(Self.describe(states), privacy: .public)
                """)
            guard allowed else {
                lastError = "You cannot turn off the last display that is on."
                return
            }
        }

        let id = display.id
        let name = display.name
        let builtins = builtinIDs
        display.isEnabled = enabled
        changing.insert(id)

        configQueue.asyncAfter(deadline: .now() + 0.3) {
            if !enabled {
                // Check again with the displays as they are now, as presets do: a display that was about to turn on
                // may have failed, or a display may have gone away since the menu showed them.
                let live = Self.liveStates(disabled: [], builtins: builtins)
                guard DisplayPolicy.canDisable([id], in: live) else {
                    Self.log.notice("""
                        Turn off \(id, privacy: .public): refused on the check again; \
                        displays: \(Self.describe(live), privacy: .public)
                        """)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self.changing.remove(id)
                            display.isEnabled = true
                            self.lastError = "You cannot turn off the last display that is on."
                            self.scheduleRefresh()
                        }
                    }
                    return
                }
            }
            let error = Self.applyEnabled(id, enabled, name: name, configure: configure)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.changing.remove(id)
                    if let error {
                        display.isEnabled = !enabled
                        self.lastError = error
                        // macOS may have changed part of the setup: show what it is now.
                        self.scheduleRefresh()
                        return
                    }
                    var disabled = self.disabled
                    disabled[id] = enabled ? nil : name
                    self.disabled = disabled
                    if enabled { self.turnedOnByApp.insert(id) }
                    self.scheduleRefresh()
                }
            }
        }
    }

    /// The displays in the list, for `DisplayPolicy`. A display with a change in progress has its new state.
    var states: [DisplayState] {
        let disabled = self.disabled
        let online = Set(Self.onlineDisplays())
        return displays.map {
            DisplayState(id: $0.id, isBuiltin: $0.isBuiltin, isOnline: online.contains($0.id),
                         isActive: $0.isEnabled, isVirtual: $0.isVirtual, isDisabledByUs: disabled[$0.id] != nil)
        }
    }

    /// The displays as macOS reports them now, for `DisplayPolicy`: the online and active ones, and `disabled`
    /// (displays we turned off), which may not be online. Safe on any thread.
    nonisolated static func liveStates(disabled: Set<CGDirectDisplayID>,
                                       builtins: Set<CGDirectDisplayID>) -> [DisplayState] {
        let online = onlineDisplays(), active = activeDisplays()
        var ids = online
        ids += active.filter { !ids.contains($0) }
        ids += disabled.sorted().filter { !ids.contains($0) }
        let reports = ids.map { id in
            DisplayReport(id: id, isBuiltin: CGDisplayIsBuiltin(id), isOnline: CGDisplayIsOnline(id),
                          isActive: CGDisplayIsActive(id), vendor: CGDisplayVendorNumber(id),
                          model: CGDisplayModelNumber(id))
        }
        return DisplayPolicy.states(online: online, active: active, reports: reports, disabled: disabled,
                                    builtins: builtins)
    }

    /// `CGGetOnlineDisplayList`. Safe on any thread.
    nonisolated static func onlineDisplays() -> [CGDirectDisplayID] { list(CGGetOnlineDisplayList) }

    /// `CGGetActiveDisplayList`. Safe on any thread.
    nonisolated static func activeDisplays() -> [CGDirectDisplayID] { list(CGGetActiveDisplayList) }

    private nonisolated static func list(
        _ get: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard get(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// The on/off decisions (`DisplayPolicy`), so a failure can be read later:
    /// `log show --predicate 'subsystem == "dev.m9t.OpenDisplay"' --info --debug`. macOS does not store debug messages
    /// by default: to see them, use `log stream --level debug` with the same predicate.
    nonisolated static let log = Logger(subsystem: "dev.m9t.OpenDisplay", category: "displays")

    /// The states with what macOS reports about each display now, for the log.
    nonisolated static func describe(_ states: [DisplayState]) -> String {
        states.map { state in
            let id = state.id
            return "\(id)[builtin \(state.isBuiltin), online \(state.isOnline), active \(state.isActive), "
                + "virtual \(state.isVirtual), ours \(state.isDisabledByUs), "
                + "macOS answers builtin \(CGDisplayIsBuiltin(id)) online \(CGDisplayIsOnline(id)) active \(CGDisplayIsActive(id)), "
                + String(format: "vendor %08X, model %08X, ", CGDisplayVendorNumber(id), CGDisplayModelNumber(id))
                + "\(Int(CGDisplayPixelsWide(id)))x\(Int(CGDisplayPixelsHigh(id)))]"
        }.joined(separator: " ")
    }

    @ObservationIgnored private var isRestoring = false
    /// Tries after a failed attempt to turn a display on again, before the next display change. The limit is per chain:
    /// each refresh starts a new chain at 0, so if a failed attempt makes macOS post a display change, the attempts go
    /// on every 3 to 5 seconds while no display is on.
    private static let restoreRetries = 3

    /// When the last physical display that is on goes away (for example, the TV is unplugged while OpenDisplay has
    /// the built-in display off), macOS does not turn another display on: it shows a virtual placeholder display, and
    /// the Mac has no screen. Then turn on a display that OpenDisplay turned off, the built-in display first.
    /// `refresh` calls this: at launch, after each change of the displays, and after wake.
    private func keepADisplayOn(retry: Int = 0) {
        guard let configure = PrivateAPI.configureDisplayEnabled else { return }
        guard changing.isEmpty, !isRestoring else {
            Self.log.notice("Keep a display on: skipped (changing \(self.changing.count, privacy: .public), restoring \(self.isRestoring, privacy: .public))")
            return
        }
        let disabled = self.disabled
        let builtins = builtinIDs
        let states = Self.liveStates(disabled: Set(disabled.keys), builtins: builtins)
        let candidates = DisplayPolicy.displaysToRestore(in: states)
        guard !candidates.isEmpty else {
            // The usual case, after each display change: only at debug level.
            Self.log.debug("Keep a display on: nothing to turn on; displays: \(Self.describe(states), privacy: .public)")
            return
        }
        Self.log.notice("""
            Keep a display on: turn on \(candidates, privacy: .public); \
            displays: \(Self.describe(states), privacy: .public)
            """)
        isRestoring = true
        // Wait a moment: after wake, a display can take a few seconds to come back on by itself.
        configQueue.asyncAfter(deadline: .now() + 2) {
            // Check again: the displays may have changed, also by a toggle or a preset before this in the queue.
            let states = Self.liveStates(disabled: Set(disabled.keys), builtins: builtins)
            let candidates = DisplayPolicy.displaysToRestore(in: states)
            Self.log.notice("""
                Keep a display on, check again: turn on \(candidates, privacy: .public); \
                displays: \(Self.describe(states), privacy: .public)
                """)
            var restored: CGDirectDisplayID?
            var failures: [(id: UInt32, error: String)] = []
            for id in candidates {
                if let error = Self.applyEnabled(id, true, name: disabled[id] ?? "Display \(id)", configure: configure) {
                    Self.log.error("""
                        Keep a display on: could not turn on \(id, privacy: .public): \(error, privacy: .private)
                        """)
                    failures.append((id, error))
                } else {
                    Self.log.notice("Keep a display on: turned on \(id, privacy: .public)")
                    restored = id
                    break
                }
            }
            let outcome = DisplayPolicy.restoreOutcome(restored: restored, failures: failures, in: states,
                                                       attempt: retry, maxRetries: Self.restoreRetries)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.isRestoring = false
                    guard let restored else {
                        // A display that failed keeps its mark in `disabled`, so the next check tries it again.
                        if let error = outcome.error { self.lastError = error }
                        // Right after a display goes away, macOS may refuse. Try a few more times, not forever.
                        if outcome.retries {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                MainActor.assumeIsolated { self.keepADisplayOn(retry: retry + 1) }
                            }
                        }
                        return
                    }
                    var disabled = self.disabled
                    disabled[restored] = nil
                    self.disabled = disabled
                    self.byID[restored]?.isEnabled = true
                    self.turnedOnByApp.insert(restored)
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
        return DisplayPolicy.isTrue(CGDisplayIsBuiltin(id)) ? "Built-in Display" : "Display \(id)"
    }
}

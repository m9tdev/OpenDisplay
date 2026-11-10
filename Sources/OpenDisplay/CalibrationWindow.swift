import AppKit
import DisplayPolicy
import SwiftUI

/// Calibrates the brightness of an external display by eye, against the built-in display.
///
/// Both displays show white over the full screen. In four steps, the user moves one display until it looks the same
/// as the other: at the lowest level of the external display, at the highest level of the darker display, and twice
/// in the middle (once from each display). `CalibrationMatches.fit` makes a curve from the four matches. The steps
/// and the matches are a `CalibrationFlow`.
///
/// A display without DDC can only get darker in software, and that curve is known. So it needs only the step at
/// the highest level.
@MainActor
@Observable
final class CalibrationSession {
    typealias Brighter = CalibrationTop.Brighter

    let builtin: Display
    let external: Display
    private let manager: DisplayManager
    /// The step and the matches. It keeps each match, so Back shows the earlier match again. Change it only with
    /// `handle`: after each change, both displays get the levels of the step.
    private(set) var flow: CalibrationFlow { didSet { apply() } }

    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    /// What to put back after the calibration. Also in UserDefaults while the calibration runs (see `restoreUnfinished`).
    @ObservationIgnored private var record: CalibrationRecord
    /// The display with XDR boost, turned off for the calibration. The boost does not survive a relaunch, so it is
    /// not in the record.
    @ObservationIgnored private var xdr: CGDirectDisplayID?
    /// The built-in level the calibration set last, to set it again if macOS changes it.
    @ObservationIgnored private var builtinWatch = CalibrationBuiltinWatch()
    /// The pending read of the built-in brightness after reports away from the level stop (see
    /// `CalibrationBuiltinWatch.settleCheckTime`). Each report schedules it again; `finish` cancels it.
    @ObservationIgnored private var settleCheck: DispatchWorkItem?

    private static var current: CalibrationSession?
    private static let recordKey = "calibrationInProgress"

    static func start(external: Display, manager: DisplayManager) {
        guard current == nil,
              let builtin = manager.displays.first(where: { $0.isBuiltin && $0.isEnabled && $0.hasHardwareBrightness })
        else { return }
        current = CalibrationSession(builtin: builtin, external: external, manager: manager)
    }

    private init(builtin: Display, external: Display, manager: DisplayManager) {
        self.builtin = builtin
        self.external = external
        self.manager = manager
        flow = CalibrationFlow(usesDDC: external.ddc != nil)
        xdr = XDRBoost.shared.displayID

        // Pause what changes the built-in display while the user compares.
        var autoBrightness = false
        let autoBrightnessOn = PrivateAPI.getAutoBrightness?(builtin.id, &autoBrightness) == 0 && autoBrightness
        let trueTone = PrivateAPI.trueToneClient()
        let trueToneOn = trueTone?.value(forKey: "enabled") as? Bool == true
        record = CalibrationRecord(autoBrightness: autoBrightnessOn, trueTone: trueToneOn,
                                   builtinBrightness: builtin.brightness, externalKey: external.stableKey,
                                   externalBrightness: external.brightness)
            // A crash's record that the launch has not put back yet.
            .keeping(CalibrationRecord(data: UserDefaults.standard.data(forKey: Self.recordKey)))
        // Before the changes: if the app ends without `finish` (a crash), the next launch puts them back.
        UserDefaults.standard.set(record.data, forKey: Self.recordKey)
        if autoBrightnessOn {
            _ = PrivateAPI.setAutoBrightness?(builtin.id, false)
        }
        if trueToneOn {
            trueTone?.setValue(false, forKey: "enabled")
        }
        if let xdr {
            XDRBoost.shared.setEnabled(false, for: xdr)
        }
        // From here, only the calibration changes the brightness (see `CalibrationPolicy`).
        manager.calibrationBuiltinChanged = { [weak self] value in
            guard let self else { return }
            // macOS changed it, for example with the brightness keys when the app does not catch them.
            if let level = self.builtinWatch.reported(value, at: ProcessInfo.processInfo.systemUptime) {
                _ = PrivateAPI.setBrightness?(self.builtin.id, level)
            }
            self.scheduleSettleCheck()
        }
        // Saved with the result, because other monitor settings give other light.
        manager.readMonitorSettings(external)
        for display in [builtin, external] {
            display.dimming = 1
            SoftwareDimming.restore(display.id)
        }
        showWindows()
        apply()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display went away, so the calibration cannot go on.
                guard let self, Self.screen(self.builtin.id) == nil || Self.screen(self.external.id) == nil else { return }
                self.finish()
            }
        }
    }

    // MARK: Steps

    func handle(_ event: CalibrationFlow.Event) {
        flow.handle(event)
    }

    /// The slider of the current step, and the display it changes.
    var slider: (value: Binding<Double>, range: ClosedRange<Double>, display: Display)? {
        guard let slider = flow.slider else { return nil }
        let value = Binding(get: { self.flow.slider?.value ?? slider.value }, set: { self.handle(.move($0)) })
        return (value, slider.range, slider.side == .builtin ? builtin : external)
    }

    /// The selected brighter display, for the picker of the top step.
    var brighter: Binding<Brighter?> {
        Binding(get: { self.flow.brighter }, set: { if let brighter = $0 { self.handle(.choose(brighter)) } })
    }

    /// Sets both displays to the levels of the current step.
    private func apply() {
        guard let levels = flow.levels else { return }
        set(builtin: levels.builtin, external: levels.external)
    }

    /// Reads the built-in brightness once after the reports stop (see `CalibrationBuiltinWatch.settleCheckTime`).
    private func scheduleSettleCheck() {
        settleCheck?.cancel()
        settleCheck = nil
        guard let checkTime = builtinWatch.settleCheckTime else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, Self.current === self else { return }
                var value: Float = 0
                guard let get = PrivateAPI.getBrightness, get(self.builtin.id, &value) == 0,
                      let level = self.builtinWatch.settled(value, at: ProcessInfo.processInfo.systemUptime) else { return }
                _ = PrivateAPI.setBrightness?(self.builtin.id, level)
            }
        }
        settleCheck = work
        // A little after the time, so the check counts as after it.
        let delay = max(checkTime - ProcessInfo.processInfo.systemUptime, 0) + 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// - Parameters:
    ///   - builtin: The built-in display's slider position, on the macOS curve.
    ///   - external: The external display's DDC level, 0...1. Without DDC: its slider position for software dimming.
    private func set(builtin value: Double, external level: Double) {
        let builtinLevel = Float(max(value, 0.01))
        builtinWatch.calibrationSet(builtinLevel)
        _ = PrivateAPI.setBrightness?(builtin.id, builtinLevel)
        if flow.usesDDC {
            manager.setCalibrationLevel(external, level)
        } else {
            SoftwareDimming.set(BrightnessCurve.light(slider: level), for: external.id)
        }
    }

    // MARK: Finish

    func save() {
        let result = flow.result
        // Never reached through the window, which offers no Save then. Saving it would break the brightness of the
        // display (the app divides by the maximum).
        guard CalibrationPolicy.isUsable(maximum: result.maximum) else { return }
        let calibration = BrightnessCalibration(
            vendor: CGDisplayVendorNumber(external.id), model: CGDisplayModelNumber(external.id), name: external.name,
            lowest: result.lowest, gamma: result.gamma, maximum: result.maximum,
            settings: flow.usesDDC ? external.monitorSettings : nil,
            reference: BrightnessCalibration.macModel, date: Date())
        finish()
        manager.setCalibration(calibration, for: external)
    }

    func finish() {
        guard Self.current === self else { return }
        Self.current = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        windows.forEach { $0.close() }
        windows = []

        manager.calibrationBuiltinChanged = nil
        settleCheck?.cancel()
        settleCheck = nil
        if let xdr {
            XDRBoost.shared.setEnabled(true, for: xdr)
        }
        // A first DDC read that was pending at the start has ended by now, with the level from before the
        // calibration: the reads and the calibration's writes go to the monitor in order.
        let state: CalibrationRecord.External = manager.isSynced(external) ? .synced : .own(brightness: external.brightness)
        let (now, pending) = record.restoreAtEnd(builtin: builtin.isEnabled, external: state)
        Self.apply(now, builtin: builtin, external: external, manager: manager)
        // What waits for the built-in display comes back with it, as after a crash (see `restoreUnfinished`).
        if let pending {
            UserDefaults.standard.set(pending.data, forKey: Self.recordKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.recordKey)
        }
    }

    /// Ends the calibration, if one runs, and puts back what it changed. For when the app quits.
    static func finishCurrent() {
        current?.finish()
    }

    /// Puts back what a calibration changed if the app ended during it without `finish` (a crash). Call after each
    /// refresh: a part for a display that is not there stays in the record until the display comes back.
    static func restoreUnfinished(manager: DisplayManager) {
        guard CalibrationRecord(data: UserDefaults.standard.data(forKey: recordKey)) != nil else { return }
        // After the first DDC reads: then a brightness write uses the monitor's own maximum, and no read overwrites it.
        // Until then the record stays, so a quit still leaves it for the next launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + DisplayManager.ddcReadyDelay) {
            MainActor.assumeIsolated {
                // A calibration that started meanwhile took the record over (see `CalibrationRecord.keeping`), and
                // puts it back when it ends.
                guard current == nil,
                      let record = CalibrationRecord(data: UserDefaults.standard.data(forKey: recordKey)) else { return }
                let builtin = manager.displays.first { $0.isBuiltin && $0.isEnabled }
                let external = manager.displays.first { !$0.isBuiltin && $0.isEnabled && $0.stableKey == record.externalKey }
                let state: CalibrationRecord.External = if let external {
                    manager.isSynced(external) ? .synced : .own(brightness: nil)
                } else {
                    .absent
                }
                let (now, pending) = record.restoreUnfinished(builtin: builtin != nil, external: state)
                // Before the restore: if the restore itself fails, it must not run again. Only the parts for a display
                // that is not there stay.
                if let pending {
                    UserDefaults.standard.set(pending.data, forKey: recordKey)
                } else {
                    UserDefaults.standard.removeObject(forKey: recordKey)
                }
                apply(now, builtin: builtin, external: external, manager: manager)
            }
        }
    }

    private static func apply(_ restore: CalibrationRecord.Restore, builtin: Display?, external: Display?,
                              manager: DisplayManager) {
        if restore.autoBrightness, let builtin {
            _ = PrivateAPI.setAutoBrightness?(builtin.id, true)
        }
        if restore.trueTone {
            PrivateAPI.trueToneClient()?.setValue(true, forKey: "enabled")
        }
        // The built-in display first: it also sets a synced external display.
        if let brightness = restore.builtinBrightness, let builtin, builtin.isEnabled {
            manager.setBrightness(builtin, to: brightness)
        }
        if let brightness = restore.externalBrightness, let external {
            manager.setBrightness(external, to: brightness)
        }
    }

    // MARK: Windows

    private static func screen(_ id: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[key] as? CGDirectDisplayID) == id }
    }

    private func showWindows() {
        for display in [builtin, external] {
            guard let screen = Self.screen(display.id) else { continue }
            // White: the same light on each display, whatever its color profile and gamma.
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.backgroundColor = .white
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            windows.append(window)
        }

        let hosting = NSHostingController(rootView: CalibrationView(session: self))
        hosting.sizingOptions = [.preferredContentSize]
        let panel = NSWindow(contentViewController: hosting)
        panel.title = "Calibrate Brightness"
        panel.styleMask = [.titled]
        panel.level = NSWindow.Level(NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        if let screen = Self.screen(builtin.id) {
            // The window has no size yet, because SwiftUI sets it later. So use the size of the content.
            panel.setContentSize(hosting.view.fittingSize)
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        windows.append(panel)
    }
}

private struct CalibrationView: View {
    let session: CalibrationSession

    private var builtinName: String { "the built-in display" }
    private var externalName: String { session.external.name }

    var body: some View {
        // Computed once: with DDC, the fit takes a moment.
        let flow = session.flow
        let fit = flow.step == .result ? flow.result : nil
        VStack(alignment: .leading, spacing: 14) {
            if let fit {
                result(fit)
            } else {
                Text(flow.stepCount > 1 ? "Step \(flow.stepNumber) of \(flow.stepCount)" : "Match the Highest Brightness")
                    .font(.headline)
                Text(instruction)
                    .fixedSize(horizontal: false, vertical: true)
                if flow.step == .top {
                    Picker("Brighter display:", selection: session.brighter) {
                        Text("Built-in").tag(CalibrationSession.Brighter?.some(.builtin))
                        Text(externalName).tag(CalibrationSession.Brighter?.some(.external))
                        Text("Same").tag(CalibrationSession.Brighter?.some(.same))
                    }
                    .pickerStyle(.segmented)
                }
                if let slider = session.slider {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "sun.min")
                            Slider(value: slider.value, in: slider.range)
                            Image(systemName: "sun.max")
                        }
                        Text("Changes \(slider.display.isBuiltin ? builtinName : externalName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if flow.isFirstStep {
                    Text("Automatic brightness and True Tone stop until you finish. If Night Shift is on, turn it off first. If the monitor has automatic brightness, dynamic contrast, or an eco mode, turn it off too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            buttons(flow, canSave: fit.map { CalibrationPolicy.isUsable(maximum: $0.maximum) } ?? false)
        }
        .padding(20)
        .frame(width: 440)
    }

    private var instruction: String {
        switch session.flow.step {
        case .lowest:
            "\(externalName) is at its lowest brightness. Move the slider until \(builtinName) has the same brightness.\n\nLook at both displays for some seconds before you decide. Your eyes need time to adapt to low light."
        case .top where session.flow.usesDDC:
            "Both displays are at their highest brightness. Select the brighter display. Then move the slider until it has the same brightness as the other display."
        case .top:
            "Both displays are at their highest brightness. Select the brighter display. Then move the slider until it has the same brightness as the other display.\n\n\(externalName) has no brightness control over DDC, so the app makes it darker in software. If you change its brightness with its own buttons, calibrate again."
        case .middle:
            "The built-in display is at 50%. Move the slider until \(externalName) has the same brightness."
        case .middleReference:
            "\(externalName) is at the middle of its range. Move the slider until \(builtinName) has the same brightness."
        case .result:
            ""
        }
    }

    @ViewBuilder private func result(_ fit: (lowest: Double?, gamma: Double?, maximum: Double, error: Double)) -> some View {
        Text("Result")
            .font(.headline)
        if !CalibrationPolicy.isUsable(maximum: fit.maximum) {
            Label("The matches give no usable result. Start again.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let lowest = fit.lowest {
                    Text("Lowest brightness: \(percent(lowest)) of its maximum.")
                }
                Text("Highest brightness: \(comparison(fit.maximum)).")
            }
        }
        if fit.error > 1.3 {
            Label("The matches do not agree well. For a better result, do the steps again.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text("The brightness sliders of all \(externalName) displays use this result. With brightness sync, they give the same light as the built-in display.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buttons(_ flow: CalibrationFlow, canSave: Bool) -> some View {
        HStack {
            Button("Cancel") { session.finish() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if flow.step == .result {
                Button("Start Again") { session.handle(.startAgain) }
                Button("Save") { session.save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            } else {
                if !flow.isFirstStep {
                    Button("Back") { session.handle(.back) }
                }
                Button("Next") { session.handle(.next) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!flow.canGoOn)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        // Int(exactly:) is nil for a number that has no Int (infinite, or too large), where Int() would crash.
        guard let percent = Int(exactly: (value * 100).rounded()) else { return "?" }
        return "\(percent)%"
    }

    private func comparison(_ maximum: Double) -> String {
        if maximum > 1.05 { return "\(percent(maximum - 1)) brighter than \(builtinName)" }
        if maximum < 0.95 { return "\(percent(1 - maximum)) darker than \(builtinName)" }
        return "about the same as \(builtinName)"
    }
}

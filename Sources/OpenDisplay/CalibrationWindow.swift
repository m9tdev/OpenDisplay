import AppKit
import SwiftUI

/// Calibrates the brightness of an external display by eye, against the built-in display.
///
/// Both displays show white over the full screen. In four steps, the user moves one display until it looks the same
/// as the other: at the lowest level of the external display, at the highest level of the darker display, and twice
/// in the middle (once from each display). `CalibrationMatches.fit` makes a curve from the four matches.
///
/// A display without DDC can only get darker in software, and that curve is known. So it needs only the step at
/// the highest level.
@MainActor
@Observable
final class CalibrationSession {
    enum Step: Int, CaseIterable {
        case lowest, top, middle, middleReference, result
    }

    enum Brighter {
        case builtin, external, same
    }

    let builtin: Display
    let external: Display
    private let manager: DisplayManager
    /// False: the external display has no DDC, so the calibration dims it in software.
    let usesDDC: Bool
    let steps: [Step]

    var step: Step { didSet { apply() } }
    /// The positions of the sliders, so Back shows the earlier match again.
    var lowestSlider = BrightnessCurve.slider(light: ExternalCurve().lowest) { didSet { apply() } }
    var brighter: Brighter? {
        didSet {
            // The other display moves now, so it starts at its highest level.
            if brighter != oldValue { topSlider = 1 }
            apply()
        }
    }
    var topSlider = 1.0 { didSet { apply() } }
    var middleLevel = 0.2 { didSet { apply() } }
    var middleReferenceSlider = 0.5 { didSet { apply() } }

    @ObservationIgnored private var windows: [NSWindow] = []
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    /// What to put back after the calibration.
    @ObservationIgnored private var saved: (builtin: Double?, external: Double?, autoBrightness: Bool, trueTone: Bool, xdr: CGDirectDisplayID?)

    private static var current: CalibrationSession?

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
        usesDDC = external.ddc != nil
        steps = usesDDC ? Step.allCases : [.top, .result]
        step = steps[0]
        saved = (builtin.brightness, external.brightness, false, false, XDRBoost.shared.displayID)

        // Pause what changes the built-in display while the user compares.
        var autoBrightness = false
        if PrivateAPI.getAutoBrightness?(builtin.id, &autoBrightness) == 0, autoBrightness {
            _ = PrivateAPI.setAutoBrightness?(builtin.id, false)
            saved.autoBrightness = true
        }
        if let trueTone = PrivateAPI.trueToneClient(), trueTone.value(forKey: "enabled") as? Bool == true {
            trueTone.setValue(false, forKey: "enabled")
            saved.trueTone = true
        }
        if let xdr = saved.xdr {
            XDRBoost.shared.setEnabled(false, for: xdr)
        }
        manager.isCalibrating = true
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

    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }
    var stepNumber: Int { stepIndex + 1 }
    /// Without the result.
    var stepCount: Int { steps.count - 1 }

    /// The slider of the current step, and the display it changes.
    var slider: (value: Binding<Double>, range: ClosedRange<Double>, display: Display)? {
        let builtinRange = 0.01...1.0
        switch step {
        case .lowest:
            return (binding(\.lowestSlider), builtinRange, builtin)
        case .top:
            switch brighter {
            case .builtin: return (binding(\.topSlider), builtinRange, builtin)
            case .external: return (binding(\.topSlider), 0...1, external)
            case .same, nil: return nil
            }
        case .middle:
            return (binding(\.middleLevel), 0...1, external)
        case .middleReference:
            return (binding(\.middleReferenceSlider), builtinRange, builtin)
        case .result:
            return nil
        }
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<CalibrationSession, Double>) -> Binding<Double> {
        Binding(get: { self[keyPath: keyPath] }, set: { self[keyPath: keyPath] = $0 })
    }

    var canGoOn: Bool {
        step != .top || brighter != nil
    }

    func next() {
        guard stepIndex + 1 < steps.count else { return }
        step = steps[stepIndex + 1]
    }

    func back() {
        guard stepIndex > 0 else { return }
        step = steps[stepIndex - 1]
    }

    func startAgain() {
        brighter = nil
        topSlider = 1
        step = steps[0]
    }

    /// The calibration values from the matches. Without DDC, only the maximum.
    var result: (lowest: Double?, gamma: Double?, maximum: Double, error: Double) {
        guard usesDDC else {
            let maximum = switch brighter {
            case .builtin: BrightnessCurve.light(slider: topSlider)
            case .external: 1 / BrightnessCurve.light(slider: topSlider)
            case .same, nil: 1.0
            }
            return (nil, nil, maximum, 1)
        }
        let fit = matches.fit()
        return (fit.lowest, fit.gamma, fit.maximum, fit.error)
    }

    private var matches: CalibrationMatches {
        let top: CalibrationMatches.Top = switch brighter {
        case .builtin: .builtinBrighter(light: BrightnessCurve.light(slider: topSlider))
        case .external: .externalBrighter(level: topSlider)
        case .same, nil: .same
        }
        return CalibrationMatches(
            lowest: BrightnessCurve.light(slider: lowestSlider),
            top: top,
            middleLevel: middleLevel,
            middleReferenceLight: BrightnessCurve.light(slider: middleReferenceSlider))
    }

    /// Sets both displays to the levels of the current step.
    private func apply() {
        switch step {
        case .lowest:
            set(builtin: lowestSlider, external: 0)
        case .top:
            switch brighter {
            case .builtin: set(builtin: topSlider, external: 1)
            case .external: set(builtin: 1, external: topSlider)
            case .same, nil: set(builtin: 1, external: 1)
            }
        case .middle:
            set(builtin: 0.5, external: middleLevel)
        case .middleReference:
            set(builtin: middleReferenceSlider, external: CalibrationMatches.middleReferenceLevel)
        case .result:
            break
        }
    }

    /// - Parameters:
    ///   - builtin: The built-in display's slider position, on the macOS curve.
    ///   - external: The external display's DDC level, 0...1. Without DDC: its slider position for software dimming.
    private func set(builtin value: Double, external level: Double) {
        _ = PrivateAPI.setBrightness?(builtin.id, Float(max(value, 0.01)))
        if usesDDC {
            external.ddc?.setLater(vcp: VCP.brightness, value: UInt16((level * Double(external.ddcMax)).rounded()))
        } else {
            SoftwareDimming.set(BrightnessCurve.light(slider: level), for: external.id)
        }
    }

    // MARK: Finish

    func save() {
        let result = result
        let calibration = BrightnessCalibration(
            vendor: CGDisplayVendorNumber(external.id), model: CGDisplayModelNumber(external.id), name: external.name,
            lowest: result.lowest, gamma: result.gamma, maximum: result.maximum,
            settings: usesDDC ? external.monitorSettings : nil,
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

        manager.isCalibrating = false
        if saved.autoBrightness {
            _ = PrivateAPI.setAutoBrightness?(builtin.id, true)
        }
        if saved.trueTone {
            PrivateAPI.trueToneClient()?.setValue(true, forKey: "enabled")
        }
        if let xdr = saved.xdr {
            XDRBoost.shared.setEnabled(true, for: xdr)
        }
        // The built-in display first: it also sets a synced external display.
        if let brightness = saved.builtin {
            manager.setBrightness(builtin, to: brightness)
        }
        if let brightness = saved.external, !manager.isSynced(external) {
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
            panel.layoutIfNeeded()
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        }
        panel.makeKeyAndOrderFront(nil)
        windows.append(panel)
    }
}

private struct CalibrationView: View {
    @Bindable var session: CalibrationSession

    private var builtinName: String { "the built-in display" }
    private var externalName: String { session.external.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if session.step == .result {
                result
            } else {
                Text(session.stepCount > 1 ? "Step \(session.stepNumber) of \(session.stepCount)" : "Match the Highest Brightness")
                    .font(.headline)
                Text(instruction)
                    .fixedSize(horizontal: false, vertical: true)
                if session.step == .top {
                    Picker("Brighter display:", selection: $session.brighter) {
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
                if session.step == session.steps[0] {
                    Text("Automatic brightness and True Tone stop until you finish. If Night Shift is on, turn it off first. If the monitor has automatic brightness, dynamic contrast, or an eco mode, turn it off too.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            buttons
        }
        .padding(20)
        .frame(width: 440)
    }

    private var instruction: String {
        switch session.step {
        case .lowest:
            "\(externalName) is at its lowest brightness. Move the slider until \(builtinName) has the same brightness.\n\nLook at both displays for some seconds before you decide. Your eyes need time to adapt to low light."
        case .top where session.usesDDC:
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

    @ViewBuilder private var result: some View {
        let fit = session.result
        Text("Result")
            .font(.headline)
        VStack(alignment: .leading, spacing: 6) {
            if let lowest = fit.lowest {
                Text("Lowest brightness: \(percent(lowest)) of its maximum.")
            }
            Text("Highest brightness: \(comparison(fit.maximum)).")
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

    private var buttons: some View {
        HStack {
            Button("Cancel") { session.finish() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if session.step == .result {
                Button("Start Again") { session.startAgain() }
                Button("Save") { session.save() }
                    .keyboardShortcut(.defaultAction)
            } else {
                if session.step != .lowest {
                    Button("Back") { session.back() }
                }
                Button("Next") { session.next() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!session.canGoOn)
            }
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func comparison(_ maximum: Double) -> String {
        if maximum > 1.05 { return "\(percent(maximum - 1)) brighter than \(builtinName)" }
        if maximum < 0.95 { return "\(percent(1 - maximum)) darker than \(builtinName)" }
        return "about the same as \(builtinName)"
    }
}

import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// The Settings window: presets and app settings, so the menu has only the display controls.
/// A grouped form, like System Settings.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(manager: DisplayManager, keyboard: KeyboardControl) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(manager: manager, keyboard: keyboard))
            // The window follows the height of the form, so it never needs to scroll.
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = "OpenDisplay Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // An app without a Dock icon is not active, and macOS refuses the normal (cooperative) activation
        // from a menu bar item. So use the older forced activation, and also bring the window to the front.
        forceActivate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        // Without this, the first switch gets the keyboard focus and shows a focus ring.
        window?.makeFirstResponder(nil)
    }

    /// `activate(ignoringOtherApps: true)`: deprecated in macOS 14, but the only call that activates an app
    /// without a Dock icon here. Called through the runtime, so the build has no deprecation warning.
    private static func forceActivate() {
        typealias Activate = @convention(c) (AnyObject, Selector, Bool) -> Void
        let selector = NSSelectorFromString("activateIgnoringOtherApps:")
        guard let method = NSApp.method(for: selector) else { return NSApp.activate() }
        unsafeBitCast(method, to: Activate.self)(NSApp, selector, true)
    }
}

private struct SettingsView: View {
    let manager: DisplayManager
    let keyboard: KeyboardControl
    private let store = PresetStore.shared

    @State private var keysEnabled = KeyboardControl.isEnabled
    @State private var hasPermission = KeyboardControl.hasPermission
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var checksForUpdates = Updates.shared.automaticallyChecks
    @State private var newPresetName = ""
    @State private var error: String?

    /// The permission and the login item can change in System Settings, so check them again.
    private let recheck = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                Toggle(isOn: Binding(get: { checksForUpdates }, set: { enabled in
                    Updates.shared.automaticallyChecks = enabled
                    checksForUpdates = enabled
                })) {
                    Text("Check for Updates Automatically")
                    Text("Once a day. OpenDisplay asks before it installs an update.")
                }
                Toggle(isOn: Binding(get: { keysEnabled }, set: setKeysEnabled)) {
                    Text("Brightness and Volume Keys")
                    Text("Also for external displays: the display under the pointer, and the display that plays the sound.")
                }
                if keysEnabled, !hasPermission {
                    LabeledContent("Needs Accessibility permission") {
                        Button("Allow…") { KeyboardControl.requestPermission() }
                    }
                    .foregroundStyle(.secondary)
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }

            if !calibratable.isEmpty {
                Section {
                    ForEach(calibratable) { display in
                        calibrationRow(display)
                    }
                } header: {
                    Text("Brightness Calibration")
                } footer: {
                    Text(hasBuiltin
                        ? "Match the brightness of an external display with the built-in display, by eye. Then their brightness sliders and brightness sync match better."
                        : "Calibration needs the built-in display. Open the lid of your Mac, then try again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(store.presets, id: \.name) { preset in
                    presetRow(preset)
                }
                HStack {
                    TextField("Name", text: $newPresetName, prompt: Text("Name, for example “Desk”"))
                        .labelsHidden()
                        .onSubmit(savePreset)
                    Button("Save Current Setup", action: savePreset)
                        .disabled(trimmedName.isEmpty)
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("A preset saves which displays are on, the main display, and the resolution, rotation, and brightness of each display.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(recheck) { _ in
            hasPermission = KeyboardControl.hasPermission
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// External displays with brightness control over DDC.
    private var calibratable: [Display] {
        manager.displays.filter { !$0.isBuiltin && $0.isEnabled && $0.hasHardwareBrightness }
    }

    private var hasBuiltin: Bool {
        manager.displays.contains { $0.isBuiltin && $0.isEnabled && $0.hasHardwareBrightness }
    }

    private func calibrationRow(_ display: Display) -> some View {
        let calibration = manager.calibration(for: display)
        return LabeledContent {
            HStack {
                if calibration != nil {
                    Button("Reset") { manager.setCalibration(nil, for: display) }
                }
                Button("Calibrate…") { CalibrationSession.start(external: display, manager: manager) }
                    .disabled(!hasBuiltin)
            }
        } label: {
            Text(display.name)
            Text(calibration.map { "Calibrated on \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "Not calibrated")
        }
    }

    private func presetRow(_ preset: Preset) -> some View {
        // Read the revision, so the "Current" label follows display changes.
        let current = manager.revision >= 0 && manager.matches(preset)
        return LabeledContent {
            HStack {
                if current {
                    Text("Current").foregroundStyle(.secondary)
                } else {
                    Button("Apply") { manager.apply(preset) }
                }
                Button(role: .destructive) {
                    store.delete(named: preset.name)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete “\(preset.name)”")
            }
        } label: {
            Text(preset.name)
        }
    }

    private var trimmedName: String {
        newPresetName.trimmingCharacters(in: .whitespaces)
    }

    private func savePreset() {
        guard !trimmedName.isEmpty else { return }
        store.save(manager.currentPreset(named: trimmedName))
        newPresetName = ""
    }

    private func setKeysEnabled(_ enabled: Bool) {
        KeyboardControl.isEnabled = enabled
        keysEnabled = enabled
        if enabled, !KeyboardControl.hasPermission {
            KeyboardControl.requestPermission()
        }
        keyboard.update()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = "Launch at Login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

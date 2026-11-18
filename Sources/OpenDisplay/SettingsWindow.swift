import AppKit
import Combine
import DisplayPolicy
import ServiceManagement
import SwiftUI

/// The Settings window: presets and app settings, so the menu has only the display controls.
/// A grouped form, like System Settings.
@MainActor
enum SettingsWindow {
    fileprivate static var window: NSWindow?

    /// Fires each second while the window is open: the permission and the login item can change in System Settings,
    /// so Settings checks them again. It stops when the window closes (the window is reused, so its views stay).
    fileprivate static let recheck = PassthroughSubject<Void, Never>()
    private static var recheckTimer: Timer?

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
            // The window lives as long as the app, so the observer is never removed.
            _ = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    recheckTimer?.invalidate()
                    recheckTimer = nil
                }
            }
        }
        if recheckTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated { recheck.send() }
            }
            RunLoop.main.add(timer, forMode: .common)
            recheckTimer = timer
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

    /// Whether a window notification is about the Settings window, not another window of the app.
    fileprivate static func isAboutSettings(_ notification: Notification) -> Bool {
        WindowNotification.isAbout(notification.object as AnyObject?, window: window)
    }
}

private struct SettingsView: View {
    let manager: DisplayManager
    let keyboard: KeyboardControl
    private let store = PresetStore.shared

    @State private var keysEnabled = KeyboardControl.isEnabled
    @State private var hasPermission = KeyboardControl.hasPermission
    private static let coffeeURL = URL(string: "https://buymeacoffee.com/m9tdev")!

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var checksForUpdates = Updates.shared.automaticallyChecks
    @State private var newPresetName = ""
    /// The Launch at Login error. It goes when the login item is fixed in System Settings.
    @State private var loginItemMessage = LoginItemMessage()
    /// The result of the last Apply or the reason it changed nothing, shown under the presets.
    @State private var applyMessage = PresetPolicy.ApplyMessage()

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
                if let error = loginItemMessage.text {
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
                if let message = applyMessage.text {
                    Text(message).foregroundStyle(.red)
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

            Section {
                LabeledContent {
                    Button {
                        NSWorkspace.shared.open(Self.coffeeURL)
                    } label: {
                        Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                    }
                } label: {
                    Text("Support OpenDisplay")
                    Text("OpenDisplay is free. If it is useful to you, you can buy me a coffee.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        // The window is reused: an old preset message must not show the next time it opens.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if SettingsWindow.isAboutSettings(notification) { applyMessage.close() }
        }
        .onReceive(SettingsWindow.recheck) { _ in
            hasPermission = KeyboardControl.hasPermission
            recheckLoginItem()
        }
        // Also check at once when Settings is shown, and when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard SettingsWindow.isAboutSettings(notification) else { return }
            // The permission can have changed while Settings was closed, when the timer does not run.
            hasPermission = KeyboardControl.hasPermission
            recheckLoginItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            recheckLoginItem()
        }
    }

    /// External displays. Without DDC, the calibration uses software dimming.
    private var calibratable: [Display] {
        manager.displays.filter { !$0.isBuiltin && $0.isEnabled }
    }

    private var hasBuiltin: Bool {
        manager.displays.contains { $0.isBuiltin && $0.isEnabled && $0.hasHardwareBrightness }
    }

    private func calibrationRow(_ display: Display) -> some View {
        let calibration = manager.calibration(for: display)
        let changed = calibration?.changedSettings(display.monitorSettings) ?? []
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
            if !changed.isEmpty {
                Text("Calibrated with other monitor settings (\(changed.joined(separator: ", ").lowercased())). Calibrate again.")
                    .foregroundStyle(.orange)
            }
        }
        // The settings can change with the monitor's own buttons, so read them each time the Settings window becomes
        // key (opens, or the user comes back to it). Not for other windows: each read goes over DDC.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if SettingsWindow.isAboutSettings(notification) { manager.readMonitorSettings(display) }
        }
        .onAppear { manager.readMonitorSettings(display) }
    }

    private func presetRow(_ preset: Preset) -> some View {
        let current = manager.matches(preset)
        return LabeledContent {
            HStack {
                if current {
                    Text("Current").foregroundStyle(.secondary)
                } else {
                    Button("Apply") { applyPreset(preset) }
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

    private func applyPreset(_ preset: Preset) {
        let run = applyMessage.start()
        manager.apply(preset) { applyMessage.finish(run, message: $0) }
    }

    private func savePreset() {
        applyMessage.clear()
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
            loginItemMessage.succeeded()
        } catch {
            loginItemMessage.failed(wanted: enabled, message: "Launch at Login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// The login item can change in System Settings: show its status, and drop the error once it is as wanted.
    private func recheckLoginItem() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginItemMessage.checked(isEnabled: launchAtLogin)
    }
}

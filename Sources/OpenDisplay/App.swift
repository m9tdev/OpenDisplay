import AppKit
import CoreGraphics

@main
@MainActor
enum OpenDisplayApp {
    private static var statusMenu: StatusMenu?

    static func main() {
        if CommandLine.arguments.contains("--list") {
            printDisplays()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        applyDebugAppearance()
        showDebugBackdrop()
        let manager = DisplayManager()
        let keyboard = KeyboardControl(manager: manager)
        statusMenu = StatusMenu(manager: manager, keyboard: keyboard)
        openDebugSettings(manager: manager, keyboard: keyboard)
        app.run()
    }

    /// Debug helper: `OpenDisplay --appearance dark` (or `light`) uses that appearance for this app only,
    /// for screenshots without a change to the system appearance.
    private static func applyDebugAppearance() {
        guard let index = CommandLine.arguments.firstIndex(of: "--appearance"),
              let value = CommandLine.arguments.dropFirst(index + 1).first else { return }
        NSApp.appearance = NSAppearance(named: value == "dark" ? .darkAqua : .aqua)
    }

    private static var backdrop: NSWindow?

    /// Debug helper: `OpenDisplay --backdrop` covers the menu bar screen with a plain light or dark color
    /// (after `--appearance`), above other windows. The menu is glass, so it shows a blur of what is behind it;
    /// with the backdrop, menu screenshots look the same on every Mac.
    private static func showDebugBackdrop() {
        guard CommandLine.arguments.contains("--backdrop"), let screen = NSScreen.screens.first else { return }
        let dark = NSApp.appearance?.name == .darkAqua
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)
        window.level = .floating
        window.ignoresMouseEvents = true
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        backdrop = window
    }

    /// Debug helper: `OpenDisplay --open-settings` opens the Settings window at launch, for screenshots.
    private static func openDebugSettings(manager: DisplayManager, keyboard: KeyboardControl) {
        guard CommandLine.arguments.contains("--open-settings") else { return }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            MainActor.assumeIsolated { SettingsWindow.show(manager: manager, keyboard: keyboard) }
        }
    }

    /// Debug helper: `OpenDisplay --list` prints each display and its brightness.
    private static func printDisplays() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        ids = Array(ids.prefix(Int(count)))
        let ddc = DDCDiscovery.services(for: ids)

        for id in ids {
            let builtin = CGDisplayIsBuiltin(id) != 0
            var line = "\(id)\t\(DisplayManager.name(of: id))\tactive=\(CGDisplayIsActive(id) != 0)\tbuiltin=\(builtin)"
            if builtin {
                var value: Float = -1
                _ = PrivateAPI.getBrightness?(id, &value)
                line += "\tbrightness=\(value)"
            } else if let service = ddc[id] {
                if CommandLine.arguments.contains("--capabilities") {
                    let caps = service.capabilities()
                    print("capabilities:", caps ?? "read failed")
                    print("parsed:", caps.map { VCP.parse(capabilities: $0).sorted { $0.key < $1.key }.map { String(format: "%02X%@", $0.key, $0.value.isEmpty ? "" : "(" + $0.value.map { String(format: "%02X", $0) }.joined(separator: " ") + ")") } } ?? [])
                }
                for (name, vcp) in [("brightness", VCP.brightness), ("volume", VCP.volume), ("mute", VCP.mute), ("contrast", VCP.contrast), ("colorPreset", VCP.colorPreset), ("input", VCP.input), ("pictureMode", UInt8(0xDC))] {
                    if let result = service.read(vcp: vcp) {
                        line += "\tddc \(name)=\(result.current)/\(result.max)"
                    } else {
                        line += "\tddc \(name) read failed"
                    }
                }
            } else {
                line += "\tno ddc service"
            }
            print(line)
        }
    }
}

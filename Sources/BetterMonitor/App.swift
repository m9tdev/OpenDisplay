import AppKit
import CoreGraphics

@main
@MainActor
enum BetterMonitorApp {
    private static var statusMenu: StatusMenu?

    static func main() {
        if CommandLine.arguments.contains("--list") {
            printDisplays()
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let manager = DisplayManager()
        statusMenu = StatusMenu(manager: manager, keyboard: KeyboardControl(manager: manager))
        app.run()
    }

    /// Debug helper: `BetterMonitor --list` prints each display and its brightness.
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

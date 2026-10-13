import CoreGraphics
import Foundation

/// Resolutions and refresh rates of a display, from the public display mode API.
enum DisplayModes {
    private static let nativeFlag: UInt32 = 0x0200_0000
    private static let defaultFlag: UInt32 = 0x0000_0004

    static func current(_ id: CGDirectDisplayID) -> CGDisplayMode? {
        CGDisplayCopyDisplayMode(id)
    }

    private static func all(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        // Without this option, macOS hides the HiDPI ("Retina") version of many sizes.
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    /// One mode per size, like System Settings: HiDPI only (if the display has HiDPI modes),
    /// and the same shape as the native resolution. Largest size (most space) first.
    static func resolutions(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        guard let current = current(id) else { return [] }
        let modes = all(id)
        let native = modes.filter { $0.ioFlags & nativeFlag != 0 }.max { $0.pixelWidth < $1.pixelWidth } ?? current
        let aspect = Double(native.pixelWidth) / Double(native.pixelHeight)

        let hiDPI = modes.filter(\.isHiDPI)
        let pool = (hiDPI.isEmpty ? modes : hiDPI).filter {
            abs(Double($0.width) / Double($0.height) - aspect) < 0.02
        }

        // For each size, keep the current refresh rate if the size has it, else the highest one.
        func score(_ mode: CGDisplayMode) -> (Int, Double) {
            (mode.refreshRate == current.refreshRate ? 1 : 0, mode.refreshRate)
        }
        var bySize: [String: CGDisplayMode] = [:]
        for mode in pool {
            let key = "\(mode.width)x\(mode.height)"
            if let kept = bySize[key], score(kept) >= score(mode) { continue }
            bySize[key] = mode
        }
        // The current mode is always in the list, also when it has another shape.
        bySize["\(current.width)x\(current.height)"] = current
        return bySize.values.sorted { $0.width > $1.width }
    }

    /// The refresh rates at the current size. Highest first.
    static func refreshRates(_ id: CGDirectDisplayID) -> [CGDisplayMode] {
        guard let current = current(id) else { return [] }
        var byRate: [Int: CGDisplayMode] = [:]
        for mode in all(id)
        where mode.width == current.width && mode.height == current.height && mode.pixelWidth == current.pixelWidth
            && mode.refreshRate > 0 {
            byRate[Int((mode.refreshRate * 100).rounded())] = mode
        }
        byRate[Int((current.refreshRate * 100).rounded())] = current
        return byRate.values.sorted { $0.refreshRate > $1.refreshRate }
    }

    /// The mode with this size and refresh rate, if the display has it.
    static func find(_ id: CGDirectDisplayID, width: Int, height: Int, pixelWidth: Int, refreshRate: Double) -> CGDisplayMode? {
        all(id).first {
            $0.width == width && $0.height == height && $0.pixelWidth == pixelWidth && abs($0.refreshRate - refreshRate) < 0.01
        }
    }

    static func isCurrent(_ mode: CGDisplayMode, of id: CGDirectDisplayID) -> Bool {
        current(id)?.ioDisplayModeID == mode.ioDisplayModeID
    }

    static func resolutionTitle(_ mode: CGDisplayMode) -> String {
        let title = "\(mode.width) × \(mode.height)"
        return mode.ioFlags & defaultFlag != 0 ? "\(title) (Default)" : title
    }

    static func refreshRateTitle(_ mode: CGDisplayMode) -> String {
        let rate = mode.refreshRate
        return rate == rate.rounded() ? "\(Int(rate)) Hz" : String(format: "%.2f Hz", rate)
    }

    /// Returns an error message, or nil on success. Blocks until macOS has changed the display, so call it off the main thread.
    static func apply(_ mode: CGDisplayMode, to id: CGDirectDisplayID) -> String? {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return "Could not start display configuration."
        }
        let result = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            return "Could not change the display mode (error \(result.rawValue))."
        }
        // Permanently, like System Settings: the mode stays after a restart.
        let completed = CGCompleteDisplayConfiguration(config, .permanently)
        return completed == .success ? nil : "Could not apply the display mode (error \(completed.rawValue))."
    }
}

private extension CGDisplayMode {
    var isHiDPI: Bool { pixelWidth > width }
}

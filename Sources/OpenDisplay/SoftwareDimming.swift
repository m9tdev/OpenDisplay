import CoreGraphics
import Foundation

/// Darkens a display in software, by scaling its color table (gamma). This works on every display,
/// also below the lowest backlight level. macOS resets the table when the app quits.
@MainActor
enum SoftwareDimming {
    private struct Table {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
    }

    /// The table of each dimmed display before we changed it, so its color calibration stays the same.
    private static var originals: [CGDirectDisplayID: Table] = [:]

    /// Displays make light from a color value on a gamma curve: light ≈ value^2.2.
    private static let gamma = 2.2

    /// - Parameter factor: The light output: 1 is the normal image, 0.2 is 20 % of its light.
    /// - Returns: False if macOS did not give or take the display's color table: then the display is not dimmed.
    @discardableResult
    static func set(_ factor: Double, for id: CGDirectDisplayID) -> Bool {
        guard factor < 1 else {
            restore(id)
            return true
        }
        guard let original = originals[id] ?? read(id) else { return false }
        // The table holds color values, not light. Scaling the values by f scales the light by f^2.2,
        // so scale the values by factor^(1/2.2) to get the light factor.
        let scale = CGGammaValue(pow(max(factor, 0), 1 / gamma))
        var red = original.red.map { $0 * scale }
        var green = original.green.map { $0 * scale }
        var blue = original.blue.map { $0 * scale }
        guard CGSetDisplayTransferByTable(id, UInt32(red.count), &red, &green, &blue) == .success else {
            // macOS kept the table it had. If an earlier call dimmed the display, put back its normal image, so the
            // display is not dimmed at all, as the caller then shows it.
            restore(id)
            return false
        }
        originals[id] = original
        return true
    }

    static func restore(_ id: CGDirectDisplayID) {
        guard var table = originals.removeValue(forKey: id) else { return }
        CGSetDisplayTransferByTable(id, UInt32(table.red.count), &table.red, &table.green, &table.blue)
    }

    /// Drops the saved table without writing it, for a display ID that now belongs to another monitor: the table is the
    /// old monitor's. If the old monitor was dimmed and macOS has not reset the table yet, the new monitor would stay
    /// dimmed, so every display gets its color table from ColorSync again: call `set` again for the other dimmed
    /// displays (the refresh does).
    static func forget(_ id: CGDirectDisplayID) {
        guard originals.removeValue(forKey: id) != nil else { return }
        CGDisplayRestoreColorSyncSettings()
    }

    static func restoreAll() {
        originals.keys.forEach(restore)
    }

    private static func read(_ id: CGDirectDisplayID) -> Table? {
        let capacity = CGDisplayGammaTableCapacity(id)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &red, &green, &blue, &count) == .success, count > 0 else {
            return nil
        }
        return Table(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }
}

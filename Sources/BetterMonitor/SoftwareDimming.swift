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
    static func set(_ factor: Double, for id: CGDirectDisplayID) {
        guard factor < 1 else { return restore(id) }
        guard let original = originals[id] ?? read(id) else { return }
        originals[id] = original
        // The table holds color values, not light. Scaling the values by f scales the light by f^2.2,
        // so scale the values by factor^(1/2.2) to get the light factor.
        let scale = CGGammaValue(pow(max(factor, 0), 1 / gamma))
        var red = original.red.map { $0 * scale }
        var green = original.green.map { $0 * scale }
        var blue = original.blue.map { $0 * scale }
        CGSetDisplayTransferByTable(id, UInt32(red.count), &red, &green, &blue)
    }

    static func restore(_ id: CGDirectDisplayID) {
        guard var table = originals.removeValue(forKey: id) else { return }
        CGSetDisplayTransferByTable(id, UInt32(table.red.count), &table.red, &table.green, &table.blue)
    }

    static func restoreAll() {
        originals.keys.forEach(restore)
    }

    /// The display's current color table, or nil if it has none (for example while it is off).
    static func currentMiddleValue(_ id: CGDirectDisplayID) -> CGGammaValue? {
        read(id).map { $0.red[$0.red.count / 2] }
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

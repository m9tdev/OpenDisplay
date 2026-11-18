/// Whether a change of the main display or of a display's rotation worked, from what macOS reports.
public enum ArrangementResult {
    /// The error message when the list of active displays could not be read, else `nil`. `result`: the `CGError` raw
    /// value of `CGGetActiveDisplayList`; `count`: how many displays it returned. An empty list is an error too: moving
    /// no display changes nothing, yet the configuration would complete without an error.
    public static func displayListError(result: Int32, count: Int) -> String? {
        if result != 0 { return "Could not read the displays (error \(result))." }
        return count == 0 ? "Could not read the displays." : nil
    }

    /// The displays whose origin a main-display change moves, in order. `displays`: each active display with the display
    /// it mirrors (`CGDisplayMirrorsDisplay`, 0 when none).
    public static func displaysToMove(_ displays: [(id: UInt32, mirrors: UInt32)]) -> [UInt32] {
        displays.map(\.id)
    }

    /// The error message for the first display that could not be moved, else `nil`. `results`: the `CGError` raw value
    /// of `CGConfigureDisplayOrigin` for each display.
    public static func originError(results: [Int32]) -> String? {
        results.first { $0 != 0 }.map { "Could not change the main display (error \($0))." }
    }

    /// The error message when the display does not have the rotation asked for, else `nil`. `readBack`: the rotation
    /// macOS reports afterwards (`CGDisplayRotation`), in degrees.
    public static func rotationError(requested: Int, readBack: Double) -> String? {
        let normalized = { (degrees: Int) in (degrees % 360 + 360) % 360 }
        return normalized(Int(readBack.rounded())) == normalized(requested)
            ? nil : "Could not rotate the display to \(requested)°."
    }
}

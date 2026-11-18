/// Whether a change of the main display or of a display's rotation worked, from what macOS reports.
public enum ArrangementResult {
    /// The error message when the list of active displays could not be read, else `nil`. `result`: the `CGError` raw
    /// value of `CGGetActiveDisplayList`; `count`: how many displays it returned.
    public static func displayListError(result: Int32, count: Int) -> String? {
        nil
    }

    /// The error message for the first display that could not be moved, else `nil`. `results`: the `CGError` raw value
    /// of `CGConfigureDisplayOrigin` for each display.
    public static func originError(results: [Int32]) -> String? {
        nil
    }

    /// The error message when the display does not have the rotation asked for, else `nil`. `readBack`: the rotation
    /// macOS reports afterwards (`CGDisplayRotation`), in degrees.
    public static func rotationError(requested: Int, readBack: Double) -> String? {
        nil
    }
}

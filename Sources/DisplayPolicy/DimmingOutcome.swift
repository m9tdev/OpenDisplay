import Foundation

/// The brightness a display really has after the app asked macOS to dim it in software.
///
/// Software dimming changes the display's color table. macOS can refuse that: it may not give the table, or not take
/// the new one. Then the display is not dimmed, so the app must not show it as dimmed.
public struct DimmingOutcome: Equatable, Sendable {
    /// The error the menu shows when macOS did not let the app dim a display.
    public static let failureMessage = "Could not dim this display in software"

    /// The slider position for the light the display really gives. `nil` if no position was known.
    public var slider: Double?
    /// The software dimming really applied: 1 is the normal image.
    public var dimming: Double
    /// The error to show, `nil` if the dimming worked or was not needed.
    public var error: String?

    /// - Parameters:
    ///   - control: How the display makes the light the slider asks for.
    ///   - slider: The slider position the app set, `nil` if none is known yet.
    ///   - dimming: The software dimming the app asked for (1: none).
    ///   - dimmed: True if macOS now dims the display by `dimming`. False: the display shows its normal image.
    public init(control: BrightnessControl, slider: Double?, dimming: Double, dimmed: Bool) {
        // Not yet: the outcome always says the dimming worked.
        self.slider = slider
        self.dimming = dimming
        self.error = nil
    }
}

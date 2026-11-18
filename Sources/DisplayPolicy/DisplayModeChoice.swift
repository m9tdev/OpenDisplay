/// A display mode the menu showed, applied later: by then the display may no longer offer it (its modes changed, it
/// turned off, or another monitor got its display ID). Apply checks the mode against the modes the display has then.
public enum DisplayModeChoice {
    /// A display mode, as `CGDisplayMode` reports it.
    public struct Mode: Equatable, Sendable {
        /// `ioDisplayModeID`: identifies the mode among the modes of one display.
        public var id: Int32
        public var width: Int
        public var height: Int
        public var pixelWidth: Int
        public var refreshRate: Double

        public init(id: Int32, width: Int, height: Int, pixelWidth: Int, refreshRate: Double) {
            self.id = id
            self.width = width
            self.height = height
            self.pixelWidth = pixelWidth
            self.refreshRate = refreshRate
        }

        func isSame(as other: Mode) -> Bool {
            id == other.id && width == other.width && height == other.height && pixelWidth == other.pixelWidth
                && abs(refreshRate - other.refreshRate) < 0.01
        }
    }

    public static let unavailableMessage = "This display mode is no longer available."

    /// The error message when the display does not offer `chosen` now, else `nil`. `offered`: the modes of the display
    /// now. The same mode ID must also mean the same size and refresh rate: another monitor may have the display ID.
    public static func unavailable(_ chosen: Mode, offered: [Mode]) -> String? {
        offered.contains { $0.isSame(as: chosen) } ? nil : unavailableMessage
    }
}

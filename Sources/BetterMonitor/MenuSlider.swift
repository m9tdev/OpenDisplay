import AppKit

/// A slider that looks like the one in the system Sound menu: a 6 pt track and a white 20 × 16 pt pill knob.
/// AppKit draws a plain NSSlider in a menu with a round knob, so this cell draws the parts itself.
final class MenuSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { MenuSliderCell.self }
        set {}
    }

    /// NSSlider has insets for its own knob shape, which move this slider 2 pt off center. This cell draws
    /// in the full bounds, so it needs none.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: MenuSliderCell.knobSize.height + 4)
    }
}

private final class MenuSliderCell: NSSliderCell {
    static let knobSize = NSSize(width: 20, height: 16)
    private static let trackHeight: CGFloat = 6

    override var knobThickness: CGFloat { Self.knobSize.width }

    override func barRect(flipped: Bool) -> NSRect {
        let bounds = controlView?.bounds ?? .zero
        return NSRect(x: bounds.minX, y: bounds.midY - Self.trackHeight / 2, width: bounds.width, height: Self.trackHeight)
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let range = maxValue - minValue
        let fraction = range > 0 ? (doubleValue - minValue) / range : 0
        let x = bar.minX + (bar.width - Self.knobSize.width) * fraction
        return NSRect(x: x, y: bar.midY - Self.knobSize.height / 2, width: Self.knobSize.width, height: Self.knobSize.height)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let radius = rect.height / 2
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        // The filled part runs to the middle of the knob, so it stays under the knob at both ends.
        var filled = rect
        filled.size.width = knobRect(flipped: flipped).midX - rect.minX
        (isEnabled ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let rect = knobRect.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        NSColor.white.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.black.withAlphaComponent(0.06).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

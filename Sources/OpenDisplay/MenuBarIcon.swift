import AppKit

/// The menu bar icon: the app icon's display, with a bezel and a sun in the screen. A template image, so
/// macOS colors it for the menu bar (light, dark, and highlighted). The sizes follow the SF Symbols in the
/// menu bar, so it looks like the system icons next to it.
///
/// `scripts/make-app-icon.py` makes the app icon from the same geometry. If you change it here, change it there too.
enum MenuBarIcon {
    static let size = NSSize(width: 20, height: 16)

    static func image() -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.set()
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "OpenDisplay"
        return image
    }

    private static func draw() {
        // The screen: only the bezel.
        // Measured from the SF Symbol "display": a 1.25 pt line and an outer corner radius of about 1.6 pt.
        let line: CGFloat = 1.25
        let radius: CGFloat = 1.6
        let screen = NSRect(x: 0.75, y: 0.5, width: 18.5, height: 12.5)
        let bezel = NSBezierPath(roundedRect: screen.insetBy(dx: line / 2, dy: line / 2), xRadius: radius - line / 2, yRadius: radius - line / 2)
        bezel.lineWidth = line
        bezel.stroke()

        // The stand: a short neck and a foot.
        let neck = NSBezierPath()
        neck.move(to: NSPoint(x: 8.7, y: screen.maxY - 0.5))
        neck.line(to: NSPoint(x: 11.3, y: screen.maxY - 0.5))
        neck.line(to: NSPoint(x: 11.6, y: 15))
        neck.line(to: NSPoint(x: 8.4, y: 15))
        neck.close()
        neck.fill()
        // The foot has the same thickness as the bezel.
        NSBezierPath(roundedRect: NSRect(x: 6, y: 16 - line, width: 8, height: line), xRadius: line / 2, yRadius: line / 2).fill()

        // The sun, in the middle of the screen.
        let center = NSPoint(x: screen.midX, y: screen.midY)
        NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)).fill()
        for index in 0..<8 {
            let angle = CGFloat(index) * .pi / 4
            let ray = NSBezierPath()
            ray.move(to: NSPoint(x: center.x + cos(angle) * 2.55, y: center.y + sin(angle) * 2.55))
            ray.line(to: NSPoint(x: center.x + cos(angle) * 3.45, y: center.y + sin(angle) * 3.45))
            ray.lineWidth = 1
            ray.lineCapStyle = .round
            ray.stroke()
        }
    }
}

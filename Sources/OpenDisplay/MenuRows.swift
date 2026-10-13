import AppKit
import Observation
import QuartzCore

// The rows of the menu. They share one grid, so all parts line up:
//
//   [ device icon ]  Display name
//                    [icon]  [ slider / label ............ value ]  [icon or chevron]
//
// While the menu is open, a row can collapse to 0 height (for example when its display turns off),
// but the menu never adds, removes, or hides items. See `StatusMenu` for why.

enum Layout {
    static let width: CGFloat = 300
    /// Left edge of the content. Measured: the same as the text of the native items ("Displays Settings…").
    static let inset: CGFloat = 16
    /// Right edge of the content. Measured: the same as the right end of the native "⌘Q".
    static let trailingInset: CGFloat = 19
    /// Where the display name starts, after the round device icon.
    static let textInset: CGFloat = inset + 34
    /// The column for the small icons at both ends of a row.
    static let iconWidth: CGFloat = 20
    static let iconInset: CGFloat = textInset - 4
    /// Where a slider track or a row label starts.
    static let controlInset: CGFloat = iconInset + iconWidth + 4
    /// The hover highlight, like the system menus.
    static let highlightInset: CGFloat = 5
    static let highlightRadius: CGFloat = 8
}

/// True while the menu is open. Rows only animate while it is open.
@MainActor
enum MenuState {
    static var isOpen = false
}

/// Re-runs `apply` each time an observed value it reads changes, as long as `owner` exists.
@MainActor
func keepUpdated<Owner: AnyObject>(_ owner: Owner, _ apply: @escaping @MainActor (Owner) -> Void) {
    withObservationTracking {
        apply(owner)
    } onChange: { [weak owner] in
        DispatchQueue.main.async {
            guard let owner else { return }
            keepUpdated(owner, apply)
        }
    }
}

// MARK: - Hover

/// Hover highlights. They are worked out when a view draws, not stored, so they cannot stay after the pointer
/// leaves. (In a menu, macOS can drop the "mouse exited" event of a view, for example when the pointer moves fast.)
///
/// A view is under the pointer when its menu item is highlighted (NSMenu tracks that reliably) and the pointer
/// is inside the view (several rows can share one item, see `RowStackView`). The views redraw when the menu
/// highlights another item (`StatusMenu`) and when the pointer moves inside an item.
@MainActor
enum Hover {
    /// The pointer position in a view, or nil if the pointer is not over the view's menu item.
    static func pointer(in view: NSView) -> NSPoint? {
        guard view.enclosingMenuItem?.isHighlighted == true, let window = view.window else { return nil }
        return view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    /// Redraws the view of a menu item and all views in it.
    static func redraw(_ item: NSMenuItem?) {
        func redraw(_ view: NSView) {
            view.needsDisplay = true
            view.subviews.forEach(redraw)
        }
        item?.view.map(redraw)
    }
}

// MARK: - Base row

/// The base of all custom rows: a height, an optional hover highlight, and a height animation.
class MenuRowView: NSView {
    /// The height while the row is visible. `setRowHeight` animates a change.
    private(set) var rowHeight: CGFloat
    /// Draw a gray rounded highlight when the mouse is over the row, like the rows in the Sound menu.
    var highlightsOnHover = false {
        didSet {
            guard highlightsOnHover != oldValue else { return }
            needsDisplay = true
            updateTrackingAreas()
        }
    }

    private var visible: Bool?
    private var animation: CADisplayLink?
    private var animationStart: (height: CGFloat, alpha: CGFloat, time: CFTimeInterval) = (0, 0, 0)
    private static let duration: CFTimeInterval = 0.2

    init(height: CGFloat) {
        rowHeight = height
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.width, height: height))
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    // The row tracks the mouse itself, because several rows can share one menu item (see `RowStackView`).
    // Then the menu item's highlight is for all of them.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard highlightsOnHover else { return }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // The pointer moved to another row in the same menu item.
    override func mouseEntered(with event: NSEvent) { Hover.redraw(enclosingMenuItem) }
    override func mouseExited(with event: NSEvent) { Hover.redraw(enclosingMenuItem) }
    override func mouseMoved(with event: NSEvent) { Hover.redraw(enclosingMenuItem) }

    override func draw(_ dirtyRect: NSRect) {
        guard highlightsOnHover, let pointer = Hover.pointer(in: self), visibleRect.contains(pointer) else { return }
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        let rect = bounds.insetBy(dx: Layout.highlightInset, dy: 0)
        NSBezierPath(roundedRect: rect, xRadius: Layout.highlightRadius, yRadius: Layout.highlightRadius).fill()
    }

    /// Shows or hides the row. In an open menu the height animates, and the menu follows it.
    func setVisible(_ show: Bool) {
        guard show != visible else { return }
        let first = visible == nil
        visible = show
        animate(now: first)
    }

    /// Changes the height of the visible row, with the same animation.
    func setRowHeight(_ height: CGFloat) {
        guard height != rowHeight else { return }
        rowHeight = height
        animate(now: visible == nil)
    }

    /// Called at each step of the height animation, so a subclass can fade in parts that need more height.
    func heightDidChange() {}

    private var target: (height: CGFloat, alpha: CGFloat) {
        visible == true ? (rowHeight, 1) : (0, 0)
    }

    private func animate(now: Bool) {
        animation?.invalidate()
        animation = nil
        guard !now, MenuState.isOpen else { return finish() }

        animationStart = (frame.height, alphaValue, CACurrentMediaTime())
        // A display link calls `step` once per screen refresh, so each frame lines up with the screen.
        // A hidden view has no window yet, so use the main screen as fallback.
        guard let link = (window?.screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(step(_:))) else {
            return finish()
        }
        // Common modes, so the link also runs while the menu tracks the mouse.
        link.add(to: .main, forMode: .common)
        animation = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = min((link.targetTimestamp - animationStart.time) / Self.duration, 1)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        let target = target
        apply(
            height: animationStart.height + (target.height - animationStart.height) * eased,
            alpha: animationStart.alpha + (target.alpha - animationStart.alpha) * eased
        )
        if t >= 1 { finish() }
    }

    private func finish() {
        animation?.invalidate()
        animation = nil
        apply(height: target.height, alpha: target.alpha)
    }

    private func apply(height: CGFloat, alpha: CGFloat) {
        setFrameSize(NSSize(width: frame.width, height: height))
        alphaValue = alpha
        // A row that starts hidden was laid out at 0 height, so lay out its contents again.
        layoutSubtreeIfNeeded()
        heightDidChange()
    }
}

/// Which displays show all their controls in the menu. The others show only brightness and volume,
/// so the menu stays short with many displays. Saved by display, so it stays after a restart.
@MainActor
@Observable
final class MenuExpansion {
    static let shared = MenuExpansion()

    private var keys = Set(UserDefaults.standard.stringArray(forKey: "expandedDisplays") ?? []) {
        didSet { UserDefaults.standard.set(keys.sorted(), forKey: "expandedDisplays") }
    }

    func isExpanded(_ display: Display) -> Bool {
        keys.contains(display.stableKey)
    }

    func toggle(_ display: Display) {
        if keys.contains(display.stableKey) { keys.remove(display.stableKey) } else { keys.insert(display.stableKey) }
    }
}

// MARK: - Title

/// Bold menu title, like "Wi-Fi" or "Sound" in the system menus.
final class TitleRowView: MenuRowView {
    init(_ title: String) {
        super.init(height: 30)
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Stack

/// Rows stacked in one menu item. The stack follows the height of its rows, so a row inside it can
/// expand and collapse fully. (A separate menu item always takes at least 1 pt, also at 0 height.)
final class RowStackView: MenuRowView {
    private let rows: [MenuRowView]

    init(_ rows: [MenuRowView]) {
        self.rows = rows
        super.init(height: rows.reduce(0) { $0 + $1.frame.height })
        for row in rows {
            row.postsFrameChangedNotifications = true
            addSubview(row)
            NotificationCenter.default.addObserver(
                self, selector: #selector(rowFrameChanged), name: NSView.frameDidChangeNotification, object: row
            )
        }
        tile()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func rowFrameChanged() {
        tile()
    }

    /// Puts the rows under each other from the top, and sets the stack to their total height.
    private func tile() {
        let total = rows.reduce(0) { $0 + $1.frame.height }
        if frame.height != total {
            setFrameSize(NSSize(width: frame.width, height: total))
        }
        var y = total
        for row in rows {
            y -= row.frame.height
            row.setFrameOrigin(NSPoint(x: 0, y: y))
        }
    }
}

// MARK: - Display

/// Round device icon, like the output icons in the Sound menu: accent color when on, gray when off.
private enum DeviceIcon {
    static let size: CGFloat = 26

    static func image(symbol: String, active: Bool) -> NSImage {
        // The drawing handler runs at draw time, so the colors follow light and dark mode.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            (active ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.1)).setFill()
            NSBezierPath(ovalIn: rect).fill()

            let tint: NSColor = active ? .white : .secondaryLabelColor
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
                // The second layer is the screen area. Clear it so only the outline shows.
                .applying(.init(paletteColors: [tint, .clear]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let origin = NSPoint(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2)
                glyph.draw(in: NSRect(origin: origin, size: glyph.size))
            }
            return true
        }
    }
}

/// A display row, like an output row in the Sound menu. A click on the round icon turns the display on or off.
/// A click on the rest of the row shows or hides all controls of the display; the chevron at the right
/// shows which, like "Other Networks" in Wi-Fi. It is a custom view because a normal menu item closes
/// the menu when you click it.
final class DisplayRowView: MenuRowView {
    private let manager: DisplayManager
    private let display: Display
    private let icon = ClickableImageView()
    private let label = NSTextField(labelWithString: "")
    private let chevron = ChevronView()

    init(manager: DisplayManager, display: Display) {
        self.manager = manager
        self.display = display
        super.init(height: 32)

        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        icon.onClick = { manager.setEnabled(display, !display.isEnabled) }
        icon.setAccessibilityRole(.button)
        for view in [icon, label, chevron] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.inset),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.textInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: Layout.iconWidth),
            chevron.heightAnchor.constraint(equalToConstant: Layout.iconWidth),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingInset),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityRole(.disclosureTriangle)

        keepUpdated(self) { view in
            let display = view.display
            view.label.stringValue = display.name
            view.icon.image = DeviceIcon.image(symbol: display.isBuiltin ? "laptopcomputer" : "display", active: display.isEnabled)
            view.icon.toolTip = display.isEnabled ? "Turn off" : "Turn on"
            view.icon.setAccessibilityLabel("\(display.name), \(display.isEnabled ? "on" : "off")")
            view.icon.setAccessibilityValue(display.isEnabled)

            // A display that is off has no controls, so the row does nothing then.
            let expanded = MenuExpansion.shared.isExpanded(display)
            view.highlightsOnHover = display.isEnabled
            view.chevron.isHidden = !display.isEnabled
            view.chevron.setExpanded(expanded)
            view.toolTip = display.isEnabled ? (expanded ? "Show fewer controls" : "Show all controls") : nil
            view.setAccessibilityLabel("All controls for \(display.name)")
            view.setAccessibilityValue(expanded)
            view.setAccessibilityEnabled(display.isEnabled)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // The icon handles its own clicks, so this is a click on the rest of the row.
    override func mouseUp(with event: NSEvent) {
        if display.isEnabled { MenuExpansion.shared.toggle(display) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard display.isEnabled else { return false }
        MenuExpansion.shared.toggle(display)
        return true
    }
}

/// A chevron that turns from › to ⌄ when its section opens, like "Other Networks" in the Wi-Fi menu.
/// It draws the symbol itself, so it can rotate it and still look like the other gray icons.
final class ChevronView: NSView {
    private var expanded: Bool?
    /// 0 is ›, 1 is ⌄.
    private var progress: CGFloat = 0
    private var animation: CADisplayLink?
    private var animationStart: (progress: CGFloat, time: CFTimeInterval) = (0, 0)
    private static let duration: CFTimeInterval = 0.2

    private static let symbol = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold).applying(.init(paletteColors: [.secondaryLabelColor])))!

    override var allowsVibrancy: Bool { true }

    func setExpanded(_ expanded: Bool) {
        guard expanded != self.expanded else { return }
        let first = self.expanded == nil
        self.expanded = expanded
        animation?.invalidate()
        animation = nil
        guard !first, MenuState.isOpen,
              let link = (window?.screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(step(_:))) else {
            progress = expanded ? 1 : 0
            needsDisplay = true
            return
        }
        animationStart = (progress, CACurrentMediaTime())
        // Common modes, so the link also runs while the menu tracks the mouse.
        link.add(to: .main, forMode: .common)
        animation = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let t = min((link.targetTimestamp - animationStart.time) / Self.duration, 1)
        // The same easing as the row heights, so the chevron turns while the controls open.
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        let target: CGFloat = expanded == true ? 1 : 0
        progress = animationStart.progress + (target - animationStart.progress) * eased
        needsDisplay = true
        if t >= 1 {
            animation?.invalidate()
            animation = nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let image = Self.symbol
        // At the right edge, like the other icons at the end of a row; it turns around its own center.
        let center = NSPoint(x: bounds.maxX - image.size.width / 2, y: bounds.midY)
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: -90 * progress)
        transform.concat()
        image.draw(in: NSRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
    }
}

// MARK: - Sliders

/// A brightness or volume slider with icons at both ends, like the Sound menu volume slider.
final class SliderRowView: MenuRowView {
    enum Kind {
        case brightness
        case volume
        case contrast
    }

    private let kind: Kind
    private let manager: DisplayManager
    private let display: Display
    private let slider = MenuSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let low = ClickableImageView()
    private let high = ClickableImageView()
    private let caption = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    /// The height without and with the caption. With it, the row matches `SteppedSliderRowView`.
    private static let plainHeight: CGFloat = 28
    private static let captionHeight: CGFloat = 44

    init(_ kind: Kind, manager: DisplayManager, display: Display) {
        self.kind = kind
        self.manager = manager
        self.display = display
        super.init(height: Self.plainHeight)

        caption.stringValue = switch kind {
        case .brightness: "Brightness"
        case .volume: "Volume"
        case .contrast: "Contrast"
        }
        for label in [caption, valueLabel] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.alphaValue = 0
        }
        valueLabel.alignment = .right

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(slid)

        let highSymbol = switch kind {
        case .brightness: "sun.max.fill"
        case .volume: "speaker.wave.3.fill"
        case .contrast: "circle.lefthalf.filled"
        }
        high.image = NSImage(systemSymbolName: highSymbol, accessibilityDescription: nil)
        // Right-aligned, so the icon ends where the native "⌘Q" and the chevrons end.
        high.imageAlignment = .alignRight
        if kind == .volume {
            // Like the system: click the small speaker to mute.
            low.onClick = { manager.setMuted(display, !display.isMuted) }
            low.setAccessibilityRole(.button)
        }

        for view in [caption, valueLabel, low, slider, high] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            // The caption sits above the slider and slides in from the top when the row grows.
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.controlInset),
            caption.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingInset),
            valueLabel.firstBaselineAnchor.constraint(equalTo: caption.firstBaselineAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: caption.trailingAnchor, constant: 8),

            low.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.iconInset),
            low.widthAnchor.constraint(equalToConstant: Layout.iconWidth),
            low.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: low.trailingAnchor, constant: 4),
            // The same distance from the bottom at both heights, so the slider stays where it is.
            slider.centerYAnchor.constraint(equalTo: bottomAnchor, constant: -Self.plainHeight / 2),
            high.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 4),
            high.widthAnchor.constraint(equalToConstant: Layout.iconWidth),
            // The symbol image has 1 pt of empty space at its right side.
            high.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingInset + 1),
            high.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
        ])

        keepUpdated(self) { view in
            view.update()
        }
    }

    override func heightDidChange() {
        // Fade the caption in while the row grows to its full height.
        let progress = (frame.height - Self.plainHeight) / (Self.captionHeight - Self.plainHeight)
        let alpha = min(max(progress, 0), 1)
        caption.alphaValue = alpha
        valueLabel.alphaValue = alpha
    }

    required init?(coder: NSCoder) { fatalError() }

    private var value: Double? {
        switch kind {
        case .brightness: display.brightness
        case .volume: display.volume
        case .contrast: display.contrast
        }
    }

    private func update() {
        let expanded = MenuExpansion.shared.isExpanded(display)
        // Contrast is only in the expanded view.
        setVisible(display.isEnabled && (kind != .contrast || expanded))
        setRowHeight(expanded ? Self.captionHeight : Self.plainHeight)
        let usable = display.isEnabled && value != nil
        slider.isEnabled = usable
        low.isEnabled = usable
        for icon in [low, high] {
            icon.contentTintColor = usable ? .secondaryLabelColor : .tertiaryLabelColor
        }

        let lowSymbol = switch kind {
        case .brightness: "sun.min.fill"
        case .volume: display.isMuted ? "speaker.slash.fill" : "speaker.fill"
        case .contrast: "circle.lefthalf.filled"
        }
        low.image = NSImage(systemSymbolName: lowSymbol, accessibilityDescription: nil)
        if kind == .contrast {
            // The same symbol at both ends, smaller at the low end, like the sun icons.
            low.symbolConfiguration = .init(scale: .small)
        }
        if kind == .volume {
            low.setAccessibilityLabel(display.isMuted ? "Unmute" : "Mute")
            low.toolTip = display.isMuted ? "Unmute" : "Mute"
        }

        if let value, window?.currentEvent?.type != .leftMouseDragged {
            // A muted display shows an empty slider, like the system volume.
            slider.doubleValue = kind == .volume && display.isMuted ? 0 : value
        }
        valueLabel.stringValue = valueText
    }

    private var valueText: String {
        guard let value else { return "" }
        if kind == .volume, display.isMuted { return "Muted" }
        return "\(Int((value * 100).rounded()))%"
    }

    @objc private func slid() {
        defer { valueLabel.stringValue = valueText }
        switch kind {
        case .brightness: manager.setBrightness(display, to: slider.doubleValue)
        case .volume: manager.setVolume(display, to: slider.doubleValue)
        case .contrast: manager.setContrast(display, to: slider.doubleValue)
        }
    }
}

/// An icon that runs `onClick` when you click it. Without `onClick` it is a plain icon.
final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if onClick == nil { super.mouseDown(with: event) }
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, let onClick else { return super.mouseUp(with: event) }
        onClick()
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, let onClick else { return false }
        onClick()
        return true
    }
}

// MARK: - Messages

/// A gray one-line message, like a disabled menu item. It collapses when there is no message.
final class MessageRowView: MenuRowView {
    private let label = NSTextField(labelWithString: "")
    private let text: @MainActor () -> String?

    /// - Parameter indented: Line up with the display names instead of the menu edge.
    init(indented: Bool, text: @escaping @MainActor () -> String?) {
        self.text = text
        super.init(height: 22)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indented ? Layout.controlInset : Layout.inset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.inset),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        keepUpdated(self) { view in
            let message = view.text()
            // Keep the old text while the row collapses.
            if let message {
                view.label.stringValue = message
                view.toolTip = message
            }
            view.setVisible(message != nil)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}


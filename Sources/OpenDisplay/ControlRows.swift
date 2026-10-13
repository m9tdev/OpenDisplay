import AppKit

// Control rows for a flat menu: no submenus. They use the grid in `Layout`: a small icon in the icon
// column, and the control or label from `Layout.controlInset` to the right edge.

// MARK: - Stepped slider

/// A slider over a list of choices (for example resolutions), with a caption that shows the current choice.
/// The choice applies when you release the mouse, because applying it can take a moment.
final class SteppedSliderRowView: MenuRowView {
    private let label = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let slider = MenuSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let choices: @MainActor () -> (titles: [String], current: Int?)
    private let apply: @MainActor (Int) -> Void
    private var titles: [String] = []

    /// - Parameters:
    ///   - choices: The titles in order (low end first) and the index of the current one.
    ///     Display modes are not observable, so `keepUpdated` runs it again after each refresh.
    ///   - apply: Applies the choice at an index.
    init(
        label text: String, lowSymbol: String, highSymbol: String,
        visible: @escaping @MainActor () -> Bool,
        choices: @escaping @MainActor () -> (titles: [String], current: Int?),
        apply: @escaping @MainActor (Int) -> Void
    ) {
        self.choices = choices
        self.apply = apply
        super.init(height: 44)

        label.stringValue = text
        for caption in [label, valueLabel] {
            caption.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            caption.textColor = .secondaryLabelColor
        }
        valueLabel.alignment = .right
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(slid)

        let low = Self.icon(lowSymbol)
        let high = Self.icon(highSymbol)
        high.imageAlignment = .alignRight
        for view in [label, valueLabel, low, slider, high] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.controlInset),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingInset),
            valueLabel.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            valueLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),

            low.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.iconInset),
            low.widthAnchor.constraint(equalToConstant: Layout.iconWidth),
            low.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.controlInset),
            slider.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            high.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 4),
            high.widthAnchor.constraint(equalToConstant: Layout.iconWidth),
            high.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingInset + 1),
            high.centerYAnchor.constraint(equalTo: slider.centerYAnchor),
        ])
        setAccessibilityLabel(text)

        keepUpdated(self) { view in
            view.setVisible(visible())
            view.reload()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func reload() {
        let (titles, current) = choices()
        self.titles = titles
        slider.maxValue = Double(max(titles.count - 1, 1))
        slider.isEnabled = titles.count > 1
        if let current, window?.currentEvent?.type != .leftMouseDragged {
            slider.doubleValue = Double(current)
            valueLabel.stringValue = titles[current]
        }
    }

    @objc private func slid() {
        // Snap to a choice, show it, and apply it when the mouse goes up.
        let index = min(max(Int(slider.doubleValue.rounded()), 0), titles.count - 1)
        slider.doubleValue = Double(index)
        valueLabel.stringValue = titles.indices.contains(index) ? titles[index] : ""
        if NSApp.currentEvent?.type != .leftMouseDragged {
            apply(index)
        }
    }

    private static func icon(_ symbol: String) -> NSImageView {
        let view = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!)
        view.contentTintColor = .secondaryLabelColor
        return view
    }
}

// MARK: - Segmented control

/// A choice without an order (for example the input of an external display), as a segmented control.
final class SegmentedRowView: MenuRowView {
    private let control = CapsuleSegmentedControl()
    private let choices: @MainActor () -> (titles: [String], current: Int?)

    init(
        symbol: String, label: String,
        visible: @escaping @MainActor () -> Bool,
        choices: @escaping @MainActor () -> (titles: [String], current: Int?),
        apply: @escaping @MainActor (Int) -> Void
    ) {
        self.choices = choices
        super.init(height: 34)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.toolTip = label
        control.onSelect = apply
        control.setAccessibilityLabel(label)
        control.toolTip = label

        for view in [icon, control] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Layout.iconInset + Layout.iconWidth / 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.controlInset),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.trailingInset),
            control.centerYAnchor.constraint(equalTo: centerYAnchor),
            control.heightAnchor.constraint(equalToConstant: CapsuleSegmentedControl.height),
        ])

        keepUpdated(self) { view in
            view.setVisible(visible())
            let (titles, current) = view.choices()
            view.control.titles = titles
            view.control.select(current)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A segmented control in the style of macOS 26 and later: a capsule track without dividers, and a raised
/// capsule for the selected choice that slides to a new choice. AppKit draws `NSSegmentedControl` in an
/// older style inside menus, so this view draws the parts itself (like `MenuSlider`).
final class CapsuleSegmentedControl: NSView {
    static let height: CGFloat = 26

    var titles: [String] = [] {
        didSet { if titles != oldValue { needsDisplay = true } }
    }
    /// Called with the index of the choice that the user clicked.
    var onSelect: (@MainActor (Int) -> Void)?

    private var selected: Int?
    /// The horizontal position of the selection, in segments (1.5 is halfway between the second and third).
    private var position: CGFloat = 0
    private var hovered: Int?
    private var pressed: Int?
    private var animation: CADisplayLink?
    private var animationStart: (position: CGFloat, time: CFTimeInterval) = (0, 0)
    private static let duration: CFTimeInterval = 0.25
    private static let inset: CGFloat = 2

    override var isFlipped: Bool { true }

    /// Shows a choice as selected. Animates when the menu is open and a choice was already selected.
    func select(_ index: Int?) {
        guard index != selected else { return }
        let animate = selected != nil && index != nil && MenuState.isOpen
        selected = index
        animation?.invalidate()
        animation = nil
        guard let index else { return needsDisplay = true }
        guard animate, let link = (window?.screen ?? NSScreen.main)?.displayLink(target: self, selector: #selector(step(_:))) else {
            position = CGFloat(index)
            needsDisplay = true
            return
        }
        animationStart = (position, CACurrentMediaTime())
        // Common modes, so the link also runs while the menu tracks the mouse.
        link.add(to: .main, forMode: .common)
        animation = link
    }

    @objc private func step(_ link: CADisplayLink) {
        guard let selected else { return }
        let t = min((link.targetTimestamp - animationStart.time) / Self.duration, 1)
        // Ease out, like a spring that settles: fast at the start, slow at the end.
        let eased = 1 - pow(1 - t, 3)
        position = animationStart.position + (CGFloat(selected) - animationStart.position) * eased
        needsDisplay = true
        if t >= 1 {
            animation?.invalidate()
            animation = nil
        }
    }

    // MARK: Drawing

    private static let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small) + 1)

    /// The left edge of each segment, and the right edge of the last one. Each segment is as wide as its
    /// title needs, plus an equal part of the free space, so long titles ("Standard") fit.
    private var edges: [CGFloat] {
        let widths = titles.map { ($0 as NSString).size(withAttributes: [.font: Self.font]).width }
        let available = bounds.width - 2 * Self.inset
        let free = max(available - widths.reduce(0, +), 0) / CGFloat(max(titles.count, 1))
        var x = Self.inset
        var edges = [x]
        for width in widths {
            x += width + free
            edges.append(x)
        }
        return edges
    }

    /// The rect of a segment. A position between two segments (while the selection slides) gives a rect
    /// between them, with an interpolated width.
    private func segmentRect(at position: CGFloat) -> NSRect {
        let edges = edges
        guard edges.count > 1 else { return .zero }
        let index = min(max(Int(position.rounded(.down)), 0), edges.count - 2)
        let next = min(index + 1, edges.count - 2)
        let fraction = position - CGFloat(index)
        let left = edges[index] + (edges[next] - edges[index]) * fraction
        let right = edges[index + 1] + (edges[next + 1] - edges[index + 1]) * fraction
        return NSRect(x: left, y: Self.inset, width: right - left, height: bounds.height - 2 * Self.inset)
    }

    private var isDark: Bool {
        // Menus use the vibrant appearances.
        let match = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        return match == .darkAqua || match == .vibrantDark
    }

    override func draw(_ dirtyRect: NSRect) {
        // The track.
        NSColor.labelColor.withAlphaComponent(isDark ? 0.10 : 0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()

        // A light highlight under the mouse, and a darker one while pressed.
        if let index = pressed ?? hovered, index != selected {
            NSColor.labelColor.withAlphaComponent(pressed != nil ? 0.10 : 0.05).setFill()
            let rect = segmentRect(at: CGFloat(index))
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        }

        // The raised capsule of the selected choice.
        if selected != nil {
            let rect = segmentRect(at: position)
            let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.35 : 0.15)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            (isDark ? NSColor.white.withAlphaComponent(0.22) : NSColor.white).setFill()
            pill.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // The titles, centered in their segments.
        for (index, title) in titles.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: Self.font,
                .foregroundColor: index == selected ? NSColor.labelColor : NSColor.secondaryLabelColor,
            ]
            let size = (title as NSString).size(withAttributes: attributes)
            let rect = segmentRect(at: CGFloat(index))
            let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
            (title as NSString).draw(in: NSRect(origin: origin, size: size).insetBy(dx: -1, dy: 0), withAttributes: attributes)
        }
    }

    // MARK: Mouse

    private func index(at event: NSEvent) -> Int? {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), !titles.isEmpty else { return nil }
        let edges = edges
        return (0..<titles.count).first { point.x < edges[$0 + 1] } ?? titles.count - 1
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(index(at: event)) }
    override func mouseEntered(with event: NSEvent) { setHovered(index(at: event)) }
    override func mouseExited(with event: NSEvent) { setHovered(nil) }

    private func setHovered(_ index: Int?) {
        guard index != hovered else { return }
        hovered = index
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: event)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        pressed = index(at: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let index = index(at: event)
        pressed = nil
        needsDisplay = true
        guard let index, index != selected else { return }
        select(index)
        onSelect?(index)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        hovered = nil
        pressed = nil
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }
    override func accessibilityValue() -> Any? { selected.map { titles[$0] } }
}

// MARK: - Toggle and action rows

/// A small round icon, like `DeviceIcon` in the display rows: accent color when on, gray when off.
enum RoundIcon {
    static func image(symbol: String, active: Bool, size: CGFloat) -> NSImage {
        // The drawing handler runs at draw time, so the colors follow light and dark mode.
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            (active ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.1)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .semibold)
                .applying(.init(paletteColors: [active ? .white : .secondaryLabelColor]))
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let origin = NSPoint(x: rect.midX - glyph.size.width / 2, y: rect.midY - glyph.size.height / 2)
                glyph.draw(in: NSRect(origin: origin, size: glyph.size))
            }
            return true
        }
    }
}

/// A row with a small round icon and a label. A click runs the action; the menu stays open.
/// As a toggle, the icon is blue when the setting is on, like the display rows and Control Center.
final class ToggleRowView: MenuRowView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let action: @MainActor (NSEvent.ModifierFlags) -> Void
    private var render: @MainActor () -> Void = {}

    /// - Parameters:
    ///   - isOn: For a toggle, whether it is on. For an action (`nil`), the icon is always gray.
    ///   - subtitle: An optional second line, in gray.
    ///   - action: Runs on a click, with the modifier keys (for example ⌥ to delete a preset).
    init(
        symbol: String, label text: String,
        visible: @escaping @MainActor () -> Bool = { true },
        isOn: (@MainActor () -> Bool)?,
        subtitle subtitleText: (@MainActor () -> String?)? = nil,
        action: @escaping @MainActor (NSEvent.ModifierFlags) -> Void
    ) {
        self.action = action
        let hasSubtitle = subtitleText != nil
        super.init(height: hasSubtitle ? 38 : 28)
        highlightsOnHover = true

        label.stringValue = text
        label.font = .menuFont(ofSize: 0)
        label.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitle.textColor = .secondaryLabelColor
        for view in [icon, label, subtitle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.iconInset),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.controlInset),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.trailingInset),
            subtitle.leadingAnchor.constraint(equalTo: label.leadingAnchor),
            subtitle.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Layout.trailingInset),
        ])
        if hasSubtitle {
            NSLayoutConstraint.activate([
                label.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 1),
                subtitle.topAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            ])
        } else {
            label.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        setAccessibilityRole(isOn == nil ? .button : .checkBox)
        setAccessibilityLabel(text)

        render = { [weak self] in
            guard let self else { return }
            let on = isOn?() ?? false
            icon.image = RoundIcon.image(symbol: symbol, active: on, size: Layout.iconWidth)
            let second = subtitleText?()
            subtitle.stringValue = second ?? ""
            subtitle.isHidden = second == nil
            if isOn != nil { setAccessibilityValue(on) }
        }
        keepUpdated(self) { view in
            view.setVisible(visible())
            view.render()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseUp(with event: NSEvent) {
        action(event.modifierFlags)
        // Some settings are not observable (for example Launch at Login), so draw the new state now.
        render()
    }

    override func accessibilityPerformPress() -> Bool {
        action([])
        render()
        return true
    }
}

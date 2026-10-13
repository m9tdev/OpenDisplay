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

/// A choice without an order (for example the input of a monitor), as a segmented control.
final class SegmentedRowView: MenuRowView {
    private let control = NSSegmentedControl()
    private let choices: @MainActor () -> (titles: [String], current: Int?)
    private let apply: @MainActor (Int) -> Void

    init(
        symbol: String, label: String,
        visible: @escaping @MainActor () -> Bool,
        choices: @escaping @MainActor () -> (titles: [String], current: Int?),
        apply: @escaping @MainActor (Int) -> Void
    ) {
        self.choices = choices
        self.apply = apply
        super.init(height: 30)

        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.toolTip = label
        control.controlSize = .small
        control.segmentDistribution = .fillEqually
        control.trackingMode = .selectOne
        control.target = self
        control.action = #selector(chose)
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
        ])

        keepUpdated(self) { view in
            view.setVisible(visible())
            let (titles, current) = view.choices()
            if view.control.segmentCount != titles.count { view.control.segmentCount = titles.count }
            for (index, title) in titles.enumerated() {
                view.control.setLabel(title, forSegment: index)
            }
            view.control.selectedSegment = current ?? -1
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func chose() {
        apply(control.selectedSegment)
    }
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

import AppKit

/// The controls of one display, all directly in the menu: sliders where the values have an order,
/// segmented controls for other choices, and toggle rows for on/off settings.
@MainActor
enum DisplayControls {
    /// The rows a display needs now, by key. A display that is off needs only its own row.
    static func neededRows(for display: Display, manager: DisplayManager) -> [String] {
        guard display.isEnabled else { return [] }
        let id = display.id
        let capabilities = display.capabilities.codes
        var rows = ["brightness"]
        if display.supportsVolume { rows.append("volume") }
        if capabilities[VCP.contrast] != nil { rows.append("contrast") }
        rows.append("resolution")
        if display.refreshRates.count > 1 { rows.append("refreshRate") }
        if DisplayArrangement.canRotate(id) { rows.append("rotation") }
        if (capabilities[VCP.input]?.count ?? 0) > 1 { rows.append("input") }
        if !(capabilities[VCP.colorPreset] ?? []).isEmpty { rows.append("colorPreset") }
        if manager.displays.filter(\.isEnabled).count > 1 { rows.append("main") }
        if !display.isBuiltin, manager.displays.contains(where: \.isBuiltin) { rows.append("sync") }
        if XDRBoost.isSupported(id) { rows.append("xdr") }
        if display.errorMessage != nil { rows.append("error") }
        return rows.map { "\(id).\($0)" }
    }

    static func row(_ key: String, manager: DisplayManager, display: Display) -> MenuRowView? {
        let id = display.id
        // Only brightness and volume are in the short view.
        let visible = { display.isEnabled && MenuExpansion.shared.isExpanded(display) }
        switch key {
        case "brightness": return SliderRowView(.brightness, manager: manager, display: display)
        case "volume": return SliderRowView(.volume, manager: manager, display: display)
        case "contrast": return SliderRowView(.contrast, manager: manager, display: display)

        case "resolution":
            // Larger text at the left, more space at the right, like System Settings.
            return SteppedSliderRowView(
                label: "Resolution", lowSymbol: "textformat.size.larger", highSymbol: "textformat.size.smaller", visible: visible,
                choices: {
                    modeChoices(display.resolutions, title: DisplayModes.resolutionTitle, display: display, manager: manager)
                }
            )

        case "refreshRate":
            return SteppedSliderRowView(
                label: "Refresh Rate", lowSymbol: "tortoise.fill", highSymbol: "hare.fill", visible: visible,
                choices: {
                    modeChoices(display.refreshRates, title: DisplayModes.refreshRateTitle, display: display, manager: manager)
                }
            )

        case "rotation":
            let rotations = DisplayArrangement.rotations
            return SegmentedRowView(
                symbol: "rotate.right", label: "Rotation", visible: visible,
                choices: {
                    let choices = rotations.map { degrees in
                        MenuChoice(title: degrees == 0 ? "Standard" : "\(degrees)°") {
                            manager.setRotation(display, degrees)
                        }
                    }
                    return (choices, rotations.firstIndex(of: display.rotation))
                }
            )

        case "input":
            return SegmentedRowView(
                symbol: "cable.connector", label: "Input", visible: visible,
                choices: {
                    let inputs = display.capabilities.codes[VCP.input] ?? []
                    let vendor = CGDisplayVendorNumber(display.id)
                    let choices = inputs.map { input in
                        MenuChoice(title: inputName(input, vendor: vendor)) { manager.setInput(display, input) }
                    }
                    return (choices, display.input.flatMap { inputs.firstIndex(of: $0) })
                }
            )

        case "colorPreset":
            return SegmentedRowView(
                symbol: "paintpalette", label: "Color Preset", visible: visible,
                choices: {
                    let presets = display.capabilities.codes[VCP.colorPreset] ?? []
                    let choices = presets.map { preset in
                        MenuChoice(title: colorPresetName(preset)) { manager.setColorPreset(display, preset) }
                    }
                    return (choices, display.colorPreset.flatMap { presets.firstIndex(of: $0) })
                }
            )

        case "main":
            return ToggleRowView(
                symbol: "menubar.rectangle", label: "Main Display", visible: visible,
                isOn: { display.isMain },
                action: { _ in if !display.isMain { manager.setMain(display) } }
            )

        case "sync":
            return ToggleRowView(
                symbol: "link", label: "Sync with Built-in Display", visible: visible,
                isOn: { manager.isSynced(display) },
                action: { _ in manager.setSynced(display, !manager.isSynced(display)) }
            )

        case "xdr":
            let row = ToggleRowView(
                symbol: "sun.max.fill", label: "Extra Brightness (XDR)", visible: visible,
                isOn: { XDRBoost.shared.isOn(id) },
                action: { _ in XDRBoost.shared.setEnabled(!XDRBoost.shared.isOn(id), for: id) }
            )
            row.toolTip = "Up to 2× brighter than the normal maximum, for use in bright light. Uses more battery."
            return row

        case "error":
            return MessageRowView(indented: true) { display.isEnabled ? display.errorMessage : nil }

        default:
            return nil
        }
    }

    /// The choices of a display mode row, low end first (the lists are largest first), and the index of the display's
    /// mode. Each choice applies its own mode.
    private static func modeChoices(
        _ modes: [CGDisplayMode], title: (CGDisplayMode) -> String, display: Display, manager: DisplayManager
    ) -> (choices: [MenuChoice], current: Int?) {
        let modes = Array(modes.reversed())
        let current = display.mode?.ioDisplayModeID
        let choices = modes.map { mode in MenuChoice(title: title(mode)) { manager.setMode(display, mode) } }
        return (choices, modes.firstIndex { $0.ioDisplayModeID == current })
    }

    // MARK: Names

    // From the VESA Monitor Control Command Set (MCCS). External displays can also use their own values.
    // Short, because they are in segmented controls.

    /// Codes above 0x12 are not in the standard, so each brand uses its own. These are the ones we know.
    private static let vendorInputNames: [UInt32: [UInt8: String]] = [
        // BenQ (for example the RD280U): 0x13 is the USB-C input.
        2513: [0x13: "USB-C"],
    ]

    static func inputName(_ value: UInt8, vendor: UInt32) -> String {
        if let name = vendorInputNames[vendor]?[value] { return name }
        let names: [UInt8: String] = [
            0x01: "VGA", 0x02: "VGA 2", 0x03: "DVI", 0x04: "DVI 2",
            0x0F: "DP", 0x10: "DP 2", 0x11: "HDMI", 0x12: "HDMI 2", 0x1B: "USB-C",
        ]
        return names[value] ?? String(format: "Input %02X", value)
    }

    static func colorPresetName(_ value: UInt8) -> String {
        let names: [UInt8: String] = [
            0x01: "sRGB", 0x02: "Native", 0x03: "4000K", 0x04: "5000K", 0x05: "6500K", 0x06: "7500K",
            0x07: "8200K", 0x08: "9300K", 0x09: "10000K", 0x0A: "11500K", 0x0B: "User", 0x0C: "User 2", 0x0D: "User 3",
        ]
        return names[value] ?? String(format: "%02X", value)
    }
}

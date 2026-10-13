import AppKit

/// The controls of one display, all directly in the menu: sliders where the values have an order,
/// segmented controls for other choices, and toggle rows for on/off settings.
@MainActor
enum DisplayControls {
    /// The rows a display needs now, by key. A display that is off needs only its own row.
    static func neededRows(for display: Display, manager: DisplayManager) -> [String] {
        guard display.isEnabled else { return [] }
        let id = display.id
        let capabilities = display.capabilities ?? [:]
        var rows = ["brightness"]
        if display.supportsVolume { rows.append("volume") }
        if capabilities[VCP.contrast] != nil { rows.append("contrast") }
        rows.append("resolution")
        if DisplayModes.refreshRates(id).count > 1 { rows.append("refreshRate") }
        if DisplayArrangement.canRotate(id) { rows.append("rotation") }
        if (capabilities[VCP.input]?.count ?? 0) > 1 { rows.append("input") }
        if !(capabilities[VCP.colorPreset] ?? []).isEmpty { rows.append("colorPreset") }
        if manager.displays.filter(\.isEnabled).count > 1 { rows.append("main") }
        if !display.isBuiltin, manager.displays.contains(where: \.isBuiltin) { rows.append("sync") }
        if XDRBoost.isSupported(id) { rows.append("xdr") }
        if display.brightnessError != nil { rows.append("error") }
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
                    _ = manager.revision
                    let modes = DisplayModes.resolutions(id).reversed()
                    return (modes.map(DisplayModes.resolutionTitle), modes.firstIndex { DisplayModes.isCurrent($0, of: id) }.map { modes.distance(from: modes.startIndex, to: $0) })
                },
                apply: { index in
                    let modes = Array(DisplayModes.resolutions(id).reversed())
                    if modes.indices.contains(index) { manager.setMode(display, modes[index]) }
                }
            )

        case "refreshRate":
            return SteppedSliderRowView(
                label: "Refresh Rate", lowSymbol: "tortoise.fill", highSymbol: "hare.fill", visible: visible,
                choices: {
                    _ = manager.revision
                    let modes = Array(DisplayModes.refreshRates(id).reversed())
                    return (modes.map(DisplayModes.refreshRateTitle), modes.firstIndex { DisplayModes.isCurrent($0, of: id) })
                },
                apply: { index in
                    let modes = Array(DisplayModes.refreshRates(id).reversed())
                    if modes.indices.contains(index) { manager.setMode(display, modes[index]) }
                }
            )

        case "rotation":
            let rotations = DisplayArrangement.rotations
            return SegmentedRowView(
                symbol: "rotate.right", label: "Rotation", visible: visible,
                choices: {
                    _ = manager.revision
                    return (rotations.map { $0 == 0 ? "Standard" : "\($0)°" }, rotations.firstIndex(of: DisplayArrangement.rotation(id)))
                },
                apply: { index in manager.setRotation(display, rotations[index]) }
            )

        case "input":
            return SegmentedRowView(
                symbol: "cable.connector", label: "Input", visible: visible,
                choices: {
                    let inputs = display.capabilities?[VCP.input] ?? []
                    return (inputs.map(inputName), display.input.flatMap { inputs.firstIndex(of: $0) })
                },
                apply: { index in
                    let inputs = display.capabilities?[VCP.input] ?? []
                    if inputs.indices.contains(index) { manager.setInput(display, inputs[index]) }
                }
            )

        case "colorPreset":
            return SegmentedRowView(
                symbol: "paintpalette", label: "Color Preset", visible: visible,
                choices: {
                    let presets = display.capabilities?[VCP.colorPreset] ?? []
                    return (presets.map(colorPresetName), display.colorPreset.flatMap { presets.firstIndex(of: $0) })
                },
                apply: { index in
                    let presets = display.capabilities?[VCP.colorPreset] ?? []
                    if presets.indices.contains(index) { manager.setColorPreset(display, presets[index]) }
                }
            )

        case "main":
            return ToggleRowView(
                symbol: "menubar.rectangle", label: "Main Display", visible: visible,
                isOn: { _ = manager.revision; return DisplayArrangement.isMain(id) },
                action: { _ in if !DisplayArrangement.isMain(id) { manager.setMain(display) } }
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
            return MessageRowView(indented: true) { display.isEnabled ? display.brightnessError : nil }

        default:
            return nil
        }
    }

    // MARK: Names

    // From the VESA Monitor Control Command Set (MCCS). External displays can also use their own values.
    // Short, because they are in segmented controls.

    static func inputName(_ value: UInt8) -> String {
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

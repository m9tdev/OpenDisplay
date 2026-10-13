import AppKit
import ApplicationServices
import CoreAudio

/// Makes the brightness and volume keys work for monitors, like on the built-in display.
///
/// - Brightness keys change the display under the mouse pointer. macOS handles the built-in display itself.
/// - Volume keys change the monitor's speakers when the monitor is the sound output (macOS cannot).
///
/// Catching the keys needs the Accessibility permission.
@MainActor
final class KeyboardControl {
    private let manager: DisplayManager
    private var tap: CFMachPort?
    private var retryTimer: Timer?

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "keyboardControl") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "keyboardControl") }
    }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    init(manager: DisplayManager) {
        self.manager = manager
        update()
    }

    /// Starts or stops catching keys. Without the permission, checks again every 2 s, so it starts when you allow it.
    func update() {
        retryTimer?.invalidate()
        retryTimer = nil
        guard Self.isEnabled else { return stop() }
        if tap == nil, !start() {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.start() else { return }
                    self.retryTimer?.invalidate()
                    self.retryTimer = nil
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    /// Shows the system prompt for the Accessibility permission.
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func start() -> Bool {
        guard Self.hasPermission else { return false }
        // Media keys arrive as "system defined" events (NX_SYSDEFINED = 14).
        let mask = CGEventMask(1 << 14)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask,
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let control = Unmanaged<KeyboardControl>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { control.handle(type, event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
    }

    // MARK: Keys

    private enum Key: Int {
        case soundUp = 0, soundDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    /// Returns nil to swallow the key, or the event to let macOS handle it.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS turns the tap off when it is too slow or when you type a password. Turn it on again.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }
        let data = nsEvent.data1
        let keyDown = (data & 0xFF00) >> 8 == 0x0A
        guard let key = Key(rawValue: (data & 0xFFFF_0000) >> 16) else { return Unmanaged.passUnretained(event) }
        // Like macOS: Option + Shift makes the steps 4 times smaller.
        let fine = nsEvent.modifierFlags.contains([.option, .shift])
        let step = fine ? 1.0 / 64 : 1.0 / 16

        switch key {
        case .brightnessUp, .brightnessDown:
            // The built-in display, and a monitor that follows it: macOS changes the built-in display,
            // and the sync changes the monitor.
            guard let display = displayUnderPointer(), !display.isBuiltin, !manager.isSynced(display),
                  let value = display.brightness else {
                return Unmanaged.passUnretained(event)
            }
            if keyDown {
                manager.setBrightness(display, to: value + (key == .brightnessUp ? step : -step))
                OSD.show(.brightness, value: display.brightness ?? 0, on: display.id)
            }
            return nil
        case .soundUp, .soundDown, .mute:
            guard let display = soundOutputDisplay(), let value = display.volume else {
                return Unmanaged.passUnretained(event)
            }
            if keyDown {
                if key == .mute {
                    manager.setMuted(display, !display.isMuted)
                } else {
                    manager.setVolume(display, to: value + (key == .soundUp ? step : -step))
                }
                OSD.show(display.isMuted ? .muted : .volume, value: display.isMuted ? 0 : display.volume ?? 0, on: display.id)
            }
            return nil
        }
    }

    private func displayUnderPointer() -> Display? {
        let point = NSEvent.mouseLocation
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let id = screen.deviceDescription[key] as? CGDirectDisplayID else { return nil }
        return manager.displays.first { $0.id == id && $0.isEnabled }
    }

    /// The monitor whose speakers are the current sound output, if any.
    private func soundOutputDisplay() -> Display? {
        guard let name = Self.defaultOutputName() else { return nil }
        return manager.displays.first { $0.isEnabled && $0.supportsVolume && (name.hasPrefix($0.name) || $0.name.hasPrefix(name)) }
    }

    private static func defaultOutputName() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }
}

/// An on-screen indicator for brightness and volume, in the style of macOS 26: a glass capsule with an icon
/// and a level bar, at the top right of the screen. (macOS 26 no longer shows the old OSD for other apps.)
@MainActor
enum OSD {
    enum Image {
        case brightness
        case volume
        case muted

        var symbol: String {
            switch self {
            case .brightness: "sun.max.fill"
            case .volume: "speaker.wave.2.fill"
            case .muted: "speaker.slash.fill"
            }
        }
    }

    private static var panel: NSPanel?
    private static var icon = NSImageView()
    private static var bar = LevelBar()
    private static var hideTimer: Timer?

    private static let size = NSSize(width: 240, height: 48)

    static func show(_ image: Image, value: Double, on id: CGDirectDisplayID) {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? CGDirectDisplayID) == id }) else { return }
        let panel = panel ?? makePanel()
        icon.image = NSImage(systemSymbolName: image.symbol, accessibilityDescription: nil)
        bar.value = min(max(value, 0), 1)

        // Under the menu bar, at the right, like the system indicators and Control Center.
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.3
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
                })
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        icon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
        icon.contentTintColor = .labelColor
        for view in [icon, bar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            bar.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            bar.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 6),
        ])

        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = size.height / 2
            glass.contentView = content
            panel.contentView = glass
        } else {
            let effect = NSVisualEffectView(frame: content.frame)
            effect.material = .hudWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = size.height / 2
            effect.addSubview(content)
            panel.contentView = effect
        }
        self.panel = panel
        return panel
    }
}

/// A level bar like the track of `MenuSlider`, without a knob.
final class LevelBar: NSView {
    var value: Double = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard value > 0 else { return }
        var filled = bounds
        filled.size.width = max(bounds.height, bounds.width * value)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}

import AppKit
import Observation
import Metal
import QuartzCore

/// Extra brightness for an XDR display: up to 2× brighter than its normal maximum for normal (SDR) content.
///
/// A full-screen layer with HDR (EDR) content multiplies the image under it by a factor above 1. Clicks pass
/// through it. macOS raises the display's HDR headroom while the layer is on screen, so the factor follows the
/// headroom, up to `maxFactor`. (Without a limit, the factor grows with the headroom, up to more than 10×.)
@MainActor
@Observable
final class XDRBoost {
    static let shared = XDRBoost()

    /// About 1000 nits at full brightness: what the XDR display can keep up over the whole screen.
    static let maxFactor = 2.0

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var layer: CAMetalLayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let device = MTLCreateSystemDefaultDevice()
    @ObservationIgnored private lazy var queue = device?.makeCommandQueue()
    private(set) var displayID: CGDirectDisplayID?

    var isEnabled: Bool { displayID != nil }

    func isOn(_ id: CGDirectDisplayID) -> Bool {
        displayID == id
    }

    static func isSupported(_ id: CGDirectDisplayID) -> Bool {
        screen(id).map { $0.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 } ?? false
    }

    func setEnabled(_ enabled: Bool, for id: CGDirectDisplayID) {
        stop()
        guard enabled, let screen = Self.screen(id), let device else { return }

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        layer.compositingFilter = "multiplyBlendMode"
        layer.isOpaque = false
        // One color over the whole screen, so a small drawable is enough.
        layer.drawableSize = CGSize(width: 16, height: 16)

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.setFrame(screen.frame, display: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.layer = layer
        displayID = id
        render(1)

        // Follow the headroom. Common modes, so it also runs while the menu is open.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The display can change size or turn off. Call after the displays change.
    func displaysChanged() {
        guard let displayID else { return }
        guard let screen = Self.screen(displayID) else { return stop() }
        window?.setFrame(screen.frame, display: false)
    }

    private func update() {
        guard let displayID, let screen = Self.screen(displayID) else { return stop() }
        render(min(Double(screen.maximumExtendedDynamicRangeColorComponentValue), Self.maxFactor))
    }

    private func render(_ factor: Double) {
        guard let layer, let queue, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor, blue: factor, alpha: 1)
        buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        window?.orderOut(nil)
        window = nil
        layer = nil
        displayID = nil
    }

    private static func screen(_ id: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[key] as? CGDirectDisplayID) == id }
    }
}

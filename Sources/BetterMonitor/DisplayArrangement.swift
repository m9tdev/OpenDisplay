import AppKit
import CoreGraphics

/// Main display and rotation.
enum DisplayArrangement {
    static func isMain(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsMain(id) != 0
    }

    /// Makes a display the main display (menu bar and Dock). macOS uses the display at (0, 0) as the main display,
    /// so move all displays by the same amount; the arrangement stays the same.
    /// Returns an error message, or nil on success. Blocks until macOS has changed the displays, so call it off the main thread.
    static func setMain(_ id: CGDirectDisplayID) -> String? {
        let origin = CGDisplayBounds(id).origin
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(UInt32(ids.count), &ids, &count)

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            return "Could not start display configuration."
        }
        for other in ids.prefix(Int(count)) {
            let bounds = CGDisplayBounds(other)
            CGConfigureDisplayOrigin(config, other, Int32(bounds.minX - origin.x), Int32(bounds.minY - origin.y))
        }
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        return result == .success ? nil : "Could not change the main display (error \(result.rawValue))."
    }

    // MARK: Rotation

    // There is no public API to rotate a display. System Settings uses MPDisplay in the private MonitorPanel framework.

    static let rotations = [0, 90, 180, 270]

    static func rotation(_ id: CGDirectDisplayID) -> Int {
        Int(CGDisplayRotation(id))
    }

    static func canRotate(_ id: CGDirectDisplayID) -> Bool {
        guard let display = monitorPanelDisplay(id) else { return false }
        typealias GetBool = @convention(c) (AnyObject, Selector) -> Bool
        return method(display, "canChangeOrientation", as: GetBool.self)(display, NSSelectorFromString("canChangeOrientation"))
    }

    /// Blocks until macOS has rotated the display, so call it off the main thread.
    static func setRotation(_ degrees: Int, for id: CGDirectDisplayID) -> String? {
        guard let display = monitorPanelDisplay(id) else { return "This macOS version does not support rotation." }
        typealias SetInt = @convention(c) (AnyObject, Selector, Int32) -> Void
        method(display, "setOrientation:", as: SetInt.self)(display, NSSelectorFromString("setOrientation:"), Int32(degrees))
        return nil
    }

    private static let monitorPanel: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY
    )

    private static func monitorPanelDisplay(_ id: CGDirectDisplayID) -> NSObject? {
        guard monitorPanel != nil, let cls = NSClassFromString("MPDisplay") else { return nil }
        let initializer = NSSelectorFromString("initWithCGSDisplayID:")
        guard class_respondsToSelector(cls, initializer),
              class_respondsToSelector(cls, NSSelectorFromString("setOrientation:")),
              // `init` takes over the object from `alloc`, so Swift must not own it (no `takeRetainedValue`).
              let allocated = (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        else { return nil }
        typealias Init = @convention(c) (AnyObject, Selector, UInt32) -> Unmanaged<NSObject>?
        let initialize = unsafeBitCast(class_getMethodImplementation(cls, initializer), to: Init.self)
        return initialize(allocated, initializer, id)?.takeRetainedValue()
    }

    private static func method<T>(_ object: NSObject, _ name: String, as _: T.Type) -> T {
        unsafeBitCast(class_getMethodImplementation(type(of: object), NSSelectorFromString(name)), to: T.self)
    }
}

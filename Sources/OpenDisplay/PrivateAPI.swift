import CoreGraphics
import Foundation
import IOKit

/// Private macOS symbols, loaded at runtime so a missing symbol never crashes the app.
enum PrivateAPI {
    private static func symbol<T>(_ name: String, in handle: UnsafeMutableRawPointer? = UnsafeMutableRawPointer(bitPattern: -2), as _: T.Type) -> T? {
        // bitPattern -2 is RTLD_DEFAULT.
        guard let ptr = dlsym(handle, name) else { return nil }
        return unsafeBitCast(ptr, to: T.self)
    }

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    // MARK: IOAVService (DDC/CI over I2C on Apple Silicon)

    typealias IOAVServiceCreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias IOAVServiceI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    static let avServiceCreate = symbol("IOAVServiceCreateWithService", as: IOAVServiceCreateWithService.self)
    static let avServiceWriteI2C = symbol("IOAVServiceWriteI2C", as: IOAVServiceI2C.self)
    static let avServiceReadI2C = symbol("IOAVServiceReadI2C", as: IOAVServiceI2C.self)

    // MARK: DisplayServices (built-in display brightness)

    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    static let getBrightness = symbol("DisplayServicesGetBrightness", in: displayServices, as: GetBrightness.self)
    static let setBrightness = symbol("DisplayServicesSetBrightness", in: displayServices, as: SetBrightness.self)

    /// Calls the callback when the display's brightness changes (keys, slider, light sensor), with the new
    /// target value as `value` in the user info. The observer is passed to the callback.
    typealias RegisterForBrightnessChanges = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    static let registerForBrightnessChanges = symbol(
        "DisplayServicesRegisterForBrightnessChangeNotifications", in: displayServices, as: RegisterForBrightnessChanges.self)

    /// Automatic brightness (from the light sensor).
    typealias GetAutoBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    typealias SetAutoBrightness = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    static let getAutoBrightness = symbol(
        "DisplayServicesAmbientLightCompensationEnabled", in: displayServices, as: GetAutoBrightness.self)
    static let setAutoBrightness = symbol(
        "DisplayServicesEnableAmbientLightCompensation", in: displayServices, as: SetAutoBrightness.self)

    // MARK: CoreBrightness (True Tone)

    private static let coreBrightness = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)

    /// `CBTrueToneClient`, with the key-value properties `supported` and `enabled`.
    static func trueToneClient() -> NSObject? {
        _ = coreBrightness
        return (NSClassFromString("CBTrueToneClient") as? NSObject.Type)?.init()
    }

    // MARK: SkyLight (display enable/disable)

    typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> CGError

    static let configureDisplayEnabled = symbol("CGSConfigureDisplayEnabled", as: ConfigureDisplayEnabled.self)
}

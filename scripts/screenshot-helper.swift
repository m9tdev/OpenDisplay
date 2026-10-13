// A helper for scripts/make-screenshots.sh.
//
//   screenshot-helper warp           Moves the pointer to the bottom left of the main display, away from the menu.
//   screenshot-helper window LAYER   Prints "x y width height id" of the first OpenDisplay window at a window layer
//                                    (101: the menu, 0: normal windows), in points.
//   screenshot-helper external-key   Prints the key of the first external display (vendor-model-serial), as
//                                    OpenDisplay saves it, for example in "expandedDisplays".
//   screenshot-helper scale          Prints the backing scale of the main display (2 on Retina displays).
import AppKit
import CoreGraphics

let arguments = CommandLine.arguments.dropFirst()

switch arguments.first {
case "warp":
    let bounds = CGDisplayBounds(CGMainDisplayID())
    CGWarpMouseCursorPosition(CGPoint(x: bounds.minX + 20, y: bounds.maxY - 20))

case "window":
    let layer = Int(arguments.dropFirst().first ?? "") ?? 0
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let window = windows.first {
        $0[kCGWindowOwnerName as String] as? String == "OpenDisplay" && $0[kCGWindowLayer as String] as? Int == layer
    }
    guard let window, let bounds = window[kCGWindowBounds as String] as? [String: Double] else { exit(1) }
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    print(Int(bounds["X"] ?? 0), Int(bounds["Y"] ?? 0), Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0), id)

case "external-key":
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
    guard let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) == 0 }) else { exit(1) }
    print("\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))")

case "scale":
    print(Int(NSScreen.screens.first?.backingScaleFactor ?? 2))

default:
    FileHandle.standardError.write("usage: screenshot-helper warp | window LAYER | external-key | scale\n".data(using: .utf8)!)
    exit(2)
}

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BetterMonitor",
            path: "Sources/BetterMonitor",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

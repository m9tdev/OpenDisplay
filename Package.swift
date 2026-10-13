// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDisplay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenDisplay",
            path: "Sources/OpenDisplay",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenDisplay",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates. Exact version: an update of Sparkle is a deliberate change (it signs and installs code).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // The on/off decisions, without macOS calls, so tests can check them.
        .target(name: "DisplayPolicy", path: "Sources/DisplayPolicy"),
        .executableTarget(
            name: "OpenDisplay",
            dependencies: ["DisplayPolicy", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/OpenDisplay",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        .testTarget(name: "DisplayPolicyTests", dependencies: ["DisplayPolicy"], path: "Tests/DisplayPolicyTests"),
    ],
    swiftLanguageModes: [.v5]
)

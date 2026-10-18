// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacCtl",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "macctl", targets: ["MacCtlCLI"]),
        .library(name: "MacCtlCore", targets: ["MacCtlCore"]),
    ],
    dependencies: [
        // Approved exception to the no-dependency rule (2026-10-16).
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "MacCtlCore"),
        .executableTarget(
            name: "MacCtlCLI",
            dependencies: [
                "MacCtlCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MacCtlCoreTests", dependencies: ["MacCtlCore"]),
    ]
)

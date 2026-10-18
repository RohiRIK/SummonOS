// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Starter",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Starter", targets: ["Starter"]),
        // Library product so Xcode makes a scheme for it: SwiftUI previews do not run in executable targets.
        .library(name: "StarterUI", targets: ["StarterUI"]),
    ],
    targets: [
        .target(name: "StarterCore"),
        .target(name: "StarterUI", dependencies: ["StarterCore"]),
        .executableTarget(name: "Starter", dependencies: ["StarterUI"]),
        .testTarget(name: "StarterCoreTests", dependencies: ["StarterCore"]),
    ]
)

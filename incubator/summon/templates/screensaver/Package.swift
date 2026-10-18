// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Starter",
    platforms: [.macOS(.v15)],
    products: [
        // A dynamic library: scripts/bundle.sh wraps it in Starter.saver.
        .library(name: "Starter", type: .dynamic, targets: ["Starter"]),
    ],
    targets: [
        .target(name: "StarterCore"),
        .target(name: "Starter", dependencies: ["StarterCore"]),
        .testTarget(name: "StarterCoreTests", dependencies: ["StarterCore"]),
    ]
)

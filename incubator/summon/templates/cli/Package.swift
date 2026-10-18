// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Starter",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "cli-starter", targets: ["Starter"]),
    ],
    targets: [
        .target(name: "StarterCore"),
        .executableTarget(name: "Starter", dependencies: ["StarterCore"]),
        .testTarget(name: "StarterCoreTests", dependencies: ["StarterCore"]),
    ]
)

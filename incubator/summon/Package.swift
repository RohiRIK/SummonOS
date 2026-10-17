// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Summon",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "summon", targets: ["SummonCLI"]),
        .executable(name: "SummonMenu", targets: ["SummonMenu"]),
        .library(name: "SummonCore", targets: ["SummonCore"]),
        // Library product so Xcode makes a scheme for it: SwiftUI previews do not run in executable targets.
        .library(name: "SummonMenuUI", targets: ["SummonMenuUI"]),
    ],
    targets: [
        .target(name: "SummonCore"),
        .executableTarget(name: "SummonCLI", dependencies: ["SummonCore"]),
        .target(name: "SummonMenuUI", dependencies: ["SummonCore"]),
        .executableTarget(name: "SummonMenu", dependencies: ["SummonMenuUI"]),
        .testTarget(name: "SummonCoreTests", dependencies: ["SummonCore"]),
    ]
)

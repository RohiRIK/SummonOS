// swift-tools-version: 6.0
import PackageDescription

// The code the app and its widget share. `Xcode/Starter.xcodeproj` builds the app and the widget extension (an
// .appex, which SwiftPM can't make) and links this package as a local package (`..`).
let package = Package(
    name: "Starter",
    platforms: [.macOS(.v15)],
    products: [
        // One product for both Xcode targets; also gives Xcode a scheme for SwiftUI previews.
        .library(name: "StarterKit", targets: ["StarterCore", "StarterUI"]),
    ],
    targets: [
        .target(name: "StarterCore"),
        .target(name: "StarterUI", dependencies: ["StarterCore"]),
        .testTarget(name: "StarterCoreTests", dependencies: ["StarterCore"]),
    ]
)

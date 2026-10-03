// swift-tools-version: 6.0
import PackageDescription

// Core and the CLI build on macOS and Linux, so logic and tests run anywhere (cloud sessions included).

let products: [Product] = [
    .executable(name: "mac-assistant", targets: ["MacAssistantCLI"]),
]

let targets: [Target] = [
    .systemLibrary(
        name: "CSQLite",
        path: "Sources/CSQLite",
        providers: [.apt(["libsqlite3-dev"])]
    ),
    .target(name: "MacAssistantCore", dependencies: ["CSQLite"]),
    .executableTarget(name: "MacAssistantCLI", dependencies: ["MacAssistantCore"]),
    .testTarget(
        name: "MacAssistantCoreTests",
        dependencies: ["MacAssistantCore"],
        resources: [.copy("Fixtures")]
    ),
]

// The macOS-only SwiftUI app (`MacAssistant`) and its `MacAssistantUI` library join here, behind
// `#if os(macOS)`, in milestone M1-UI (see PROJECT-CONTEXT.md).

let package = Package(
    name: "MacAssistant",
    platforms: [.macOS(.v15)],
    products: products,
    targets: targets
)

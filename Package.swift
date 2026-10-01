// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacOSDiktierApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DiktierApp", targets: ["DiktierApp"]),
        .executable(name: "FlowCheck", targets: ["FlowCheck"])
    ],
    targets: [
        .target(name: "FlowCore"),
        .executableTarget(name: "DiktierApp", dependencies: ["FlowCore"]),
        .executableTarget(name: "FlowCheck", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore"]),
        .testTarget(name: "FlowIntegrationTests", dependencies: ["DiktierApp", "FlowCore"])
    ],
    swiftLanguageModes: [.v5]
)

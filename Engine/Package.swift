// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlowQwenEngine",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Blaizzy/mlx-audio-swift.git",
                 revision: "b7c7971d94c4f73de910797593851d00858daf19")
    ],
    targets: [.executableTarget(name: "flow-qwen", dependencies: [
        .product(name: "MLXAudioCore", package: "mlx-audio-swift"),
        .product(name: "MLXAudioSTT", package: "mlx-audio-swift")
    ])]
)

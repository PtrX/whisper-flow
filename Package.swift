// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WhisperFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperFlowCore", targets: ["WhisperFlowCore"]),
        .executable(name: "WhisperFlowApp", targets: ["WhisperFlowApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .target(
            name: "WhisperFlowCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "WhisperFlowApp",
            dependencies: ["WhisperFlowCore"]
        ),
        .testTarget(
            name: "WhisperFlowCoreTests",
            dependencies: ["WhisperFlowCore"]
        ),
    ]
)

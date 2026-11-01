// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParakeetServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", revision: "c79c4106b954f81205113c3343e5a7e59a1089b5")
    ],
    targets: [
        .executableTarget(
            name: "ParakeetServer",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

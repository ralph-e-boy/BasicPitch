// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BasicPitch",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BasicPitch", targets: ["BasicPitch"]),
        .executable(name: "basic-pitch-cli", targets: ["BasicPitchCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "BasicPitch",
            resources: [
                .copy("Resources/nmp.mlpackage"),
            ]
        ),
        .executableTarget(
            name: "BasicPitchCLI",
            dependencies: [
                "BasicPitch",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "BasicPitchTests",
            dependencies: ["BasicPitch"],
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BasicPitch",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "BasicPitch", targets: ["BasicPitch"]),
        .library(name: "BasicPitchDemucs", targets: ["BasicPitchDemucs"]),
        .executable(name: "basic-pitch-cli", targets: ["BasicPitchCLI"]),
        .executable(name: "basic-pitch-demucs-cli", targets: ["BasicPitchDemucsCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/kylehowells/demucs-mlx-swift.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "BasicPitch",
            resources: [
                .copy("Resources/nmp.mlpackage"),
            ]
        ),
        .target(
            name: "BasicPitchDemucs",
            dependencies: [
                "BasicPitch",
                .product(name: "DemucsMLX", package: "demucs-mlx-swift"),
            ]
        ),
        .executableTarget(
            name: "BasicPitchCLI",
            dependencies: [
                "BasicPitch",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "BasicPitchDemucsCLI",
            dependencies: [
                "BasicPitchDemucs",
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

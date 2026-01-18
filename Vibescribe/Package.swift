// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VibeScribe",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "VibeScribe", targets: ["VibeScribe"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "VibeScribe",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

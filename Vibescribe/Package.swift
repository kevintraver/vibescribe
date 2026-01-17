// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Vibescribe",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Vibescribe", targets: ["Vibescribe"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio", from: "0.8.0")
    ],
    targets: [
        .executableTarget(
            name: "Vibescribe",
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

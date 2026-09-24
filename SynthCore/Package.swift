// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SynthCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SynthCore", targets: ["SynthCore"])
    ],
    targets: [
        .target(name: "SynthCore"),
        .testTarget(name: "SynthCoreTests", dependencies: ["SynthCore"])
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CostumeCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CostumeCore", targets: ["CostumeCore"]),
    ],
    targets: [
        .target(name: "CostumeCore"),
        .testTarget(name: "CostumeCoreTests", dependencies: ["CostumeCore"]),
    ]
)

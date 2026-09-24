// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Costume3DCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Costume3DCore", targets: ["Costume3DCore"]),
        .executable(name: "costume3d-blocky", targets: ["costume3d-blocky"]),
    ],
    targets: [
        .target(name: "Costume3DCore"),
        .executableTarget(name: "costume3d-blocky", dependencies: ["Costume3DCore"]),
        .testTarget(name: "Costume3DCoreTests", dependencies: ["Costume3DCore"]),
    ]
)

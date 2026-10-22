// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CropCast",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CropCast", targets: ["CropCast"]),
    ],
    targets: [
        .target(name: "CropCastCore"),
        .executableTarget(
            name: "CropCast",
            dependencies: ["CropCastCore"]
        ),
        .testTarget(
            name: "CropCastCoreTests",
            dependencies: ["CropCastCore"]
        ),
    ]
)

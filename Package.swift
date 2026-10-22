// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CropCast",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CropCast", targets: ["CropCast"]),
    ],
    dependencies: [
        .package(path: "Packages/VirtualDisplay"),
        .package(path: "Packages/RegionMirror"),
        .package(path: "Packages/RegionFrame"),
    ],
    targets: [
        .target(name: "CropCastCore"),
        .executableTarget(
            name: "CropCast",
            dependencies: [
                "CropCastCore",
                .product(name: "VirtualDisplay", package: "VirtualDisplay"),
                .product(name: "RegionMirror", package: "RegionMirror"),
                .product(name: "RegionFrame", package: "RegionFrame"),
            ]
        ),
        .testTarget(
            name: "CropCastCoreTests",
            dependencies: ["CropCastCore"]
        ),
    ]
)

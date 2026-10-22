// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RegionFrame",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RegionFrame", targets: ["RegionFrame"]),
        .executable(name: "regionframe-demo", targets: ["RegionFrameDemo"]),
    ],
    targets: [
        .target(name: "RegionFrame"),
        .executableTarget(name: "RegionFrameDemo", dependencies: ["RegionFrame"]),
        .testTarget(name: "RegionFrameTests", dependencies: ["RegionFrame"]),
    ],
    swiftLanguageModes: [.v6]
)

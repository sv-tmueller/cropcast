// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RegionMirror",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "RegionMirror", targets: ["RegionMirror"]),
        .executable(name: "regionmirror-demo", targets: ["RegionMirrorDemo"]),
    ],
    targets: [
        .target(name: "RegionMirror"),
        .executableTarget(name: "RegionMirrorDemo", dependencies: ["RegionMirror"]),
        .testTarget(name: "RegionMirrorTests", dependencies: ["RegionMirror"]),
    ],
    swiftLanguageModes: [.v6]
)

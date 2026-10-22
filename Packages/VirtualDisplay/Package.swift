// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtualDisplay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VirtualDisplay", targets: ["VirtualDisplay"]),
    ],
    targets: [
        .target(name: "VirtualDisplay"),
        .testTarget(name: "VirtualDisplayTests", dependencies: ["VirtualDisplay"]),
    ],
    swiftLanguageModes: [.v6]
)

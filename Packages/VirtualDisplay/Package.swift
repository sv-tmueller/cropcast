// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VirtualDisplay",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VirtualDisplay", targets: ["VirtualDisplay"]),
        .executable(name: "vdisplay-demo", targets: ["vdisplay-demo"]),
    ],
    targets: [
        // The only target that touches the private CGVirtualDisplay API.
        // CoreGraphics is linked explicitly so the private classes get loaded.
        .target(
            name: "CVirtualDisplayShim",
            linkerSettings: [.linkedFramework("CoreGraphics")]
        ),
        .target(
            name: "VirtualDisplay",
            dependencies: ["CVirtualDisplayShim"]
        ),
        // Pure option parsing and pass/fail logic for the demo. Not a product.
        .target(name: "VirtualDisplayDemoSupport"),
        .executableTarget(
            name: "vdisplay-demo",
            dependencies: ["VirtualDisplay", "VirtualDisplayDemoSupport"]
        ),
        .testTarget(
            name: "VirtualDisplayTests",
            dependencies: ["VirtualDisplay", "CVirtualDisplayShim", "VirtualDisplayDemoSupport"]),
    ],
    swiftLanguageModes: [.v6]
)

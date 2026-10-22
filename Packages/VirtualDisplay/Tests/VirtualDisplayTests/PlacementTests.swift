import CoreGraphics
import Testing

@testable import VirtualDisplay

struct PlacementTests {
    static let virtualSize = CGSize(width: 2560, height: 1440)

    static let mains: [CGRect] = [
        CGRect(x: 0, y: 0, width: 5120, height: 1440),
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: 0, y: 0, width: 3840, height: 2160),
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 100, y: -50, width: 1920, height: 1080),
    ]

    @Test func bottomLeftOriginOnUltrawide() {
        let main = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        let origin = Placement.origin(mainBounds: main, displaySize: Self.virtualSize)
        #expect(origin == CGPoint(x: -2560, y: 1440))
    }

    @Test func offsetsFromNonZeroMainOrigin() {
        let main = CGRect(x: 100, y: -50, width: 1920, height: 1080)
        let origin = Placement.origin(mainBounds: main, displaySize: Self.virtualSize)
        #expect(origin == CGPoint(x: 100 - 2560, y: 1030))
    }

    @Test(arguments: mains)
    func touchesMainOnlyAtItsBottomLeftCorner(main: CGRect) {
        let origin = Placement.origin(mainBounds: main, displaySize: Self.virtualSize)
        let virtual = CGRect(origin: origin, size: Self.virtualSize)
        #expect(virtual.maxX == main.minX)
        #expect(virtual.minY == main.maxY)
        let overlap = virtual.intersection(main)
        #expect(overlap.isNull || overlap.width * overlap.height == 0)
    }
}

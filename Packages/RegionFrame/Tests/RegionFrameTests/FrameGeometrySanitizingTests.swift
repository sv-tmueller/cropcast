import CoreGraphics
import Testing
@testable import RegionFrame

/// Geometry must never trap, whatever numbers arrive (decoded defaults,
/// pointer events). `Int(Double)` traps on NaN and out-of-range values, so
/// these tests feed those values to every entry point.
let hostileNumbers: [CGFloat] = [.nan, .infinity, -.infinity, 1e300, -1e300, .greatestFiniteMagnitude]

/// Displays below the 640x360 floor, but large enough for one 16x9 step.
let smallDisplays = [
    CGRect(x: 0, y: 0, width: 320, height: 180),
    CGRect(x: -500, y: -300, width: 400, height: 400),
    CGRect(x: 100, y: 50, width: 16, height: 9),
]
/// Too small for any 16x9 frame: results only have to stay finite and not trap.
let tinyDisplay = CGRect(x: 10, y: 10, width: 10, height: 5)

@Suite struct FrameGeometryRestoreSanitizingTests {
    @Test(arguments: [CGFloat.infinity, 1e300, .greatestFiniteMagnitude])
    func absurdlyWideStoredRectIsClampedToTheLargestFrame(width: CGFloat) {
        let result = FrameGeometry.restore(local: CGRect(x: 0, y: 0, width: width, height: 5), in: TestDisplays.main)
        #expect(result.size == CGSize(width: 1792, height: 1008))
        expectValid(result, in: TestDisplays.main)
    }

    @Test(arguments: TestDisplays.all, [CGFloat.nan, -CGFloat.infinity, 0, -50])
    func nonFiniteOrNonPositiveStoredSizeFallsBackToTheCentrePreset(display: CGRect, size: CGFloat) {
        for stored in [
            CGRect(x: 10, y: 10, width: size, height: 300),
            CGRect(x: 10, y: 10, width: 300, height: size),
        ] {
            #expect(FrameGeometry.restore(local: stored, in: display) == FrameGeometry.preset(.center, in: display))
        }
    }

    @Test(arguments: TestDisplays.all, hostileNumbers)
    func nonFiniteOrFarAwayStoredOriginFallsBackToTheCentrePreset(display: CGRect, value: CGFloat) {
        for stored in [
            CGRect(x: value, y: 10, width: 640, height: 360),
            CGRect(x: 10, y: value, width: 640, height: 360),
        ] {
            #expect(FrameGeometry.restore(local: stored, in: display) == FrameGeometry.preset(.center, in: display))
        }
    }

    @Test func storedRectThatMissesTheDisplayEntirelyFallsBackToTheCentrePreset() {
        let display = TestDisplays.main
        let stored = CGRect(x: 5000, y: 5000, width: 640, height: 360)
        #expect(FrameGeometry.restore(local: stored, in: display) == FrameGeometry.preset(.center, in: display))
    }

    @Test(arguments: smallDisplays)
    func smallDisplayRestoresAFrameThatFits(display: CGRect) {
        let result = FrameGeometry.restore(local: CGRect(x: 1, y: 1, width: 1e300, height: 5), in: display)
        expectValid(result, in: display)
    }
}

@Suite struct FrameGeometryResizeSanitizingTests {
    @Test(arguments: TestDisplays.all, FrameHandle.allCases)
    func hostileDeltasKeepTheInvariants(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        for value in hostileNumbers {
            for delta in [CGVector(dx: value, dy: value), CGVector(dx: value, dy: 0), CGVector(dx: 0, dy: value), CGVector(dx: value, dy: -value)] {
                expectValid(FrameGeometry.resize(start, handle: handle, by: delta, in: display), in: display)
            }
        }
    }

    @Test(arguments: TestDisplays.all, FrameHandle.allCases)
    func nanDeltaChangesNothing(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let zero = FrameGeometry.resize(start, handle: handle, by: .zero, in: display)
        let result = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: CGFloat.nan, dy: CGFloat.nan), in: display)
        #expect(result == zero)
    }

    @Test(arguments: TestDisplays.all, FrameHandle.allCases)
    func infiniteDragShrinksToTheFloorOrGrowsToTheLimit(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)
        let grow = CGVector(dx: dir.x * CGFloat.infinity, dy: dir.y * CGFloat.infinity)
        let shrink = CGVector(dx: -dir.x * CGFloat.infinity, dy: -dir.y * CGFloat.infinity)
        let big = FrameGeometry.resize(start, handle: handle, by: grow, in: display)
        let small = FrameGeometry.resize(start, handle: handle, by: shrink, in: display)
        #expect(small.size == CGSize(width: 640, height: 360))
        #expect(big.width >= start.width)
        expectValid(big, in: display)
        expectValid(small, in: display)
    }

    @Test(arguments: FrameHandle.allCases, hostileNumbers)
    func nonFiniteStartRectDoesNotTrap(handle: FrameHandle, value: CGFloat) {
        let display = TestDisplays.main
        for start in [
            CGRect(x: value, y: 0, width: 640, height: 360),
            CGRect(x: 0, y: value, width: 640, height: 360),
            CGRect(x: 0, y: 0, width: value, height: 360),
            CGRect(x: 0, y: 0, width: 640, height: value),
        ] {
            expectValid(FrameGeometry.resize(start, handle: handle, by: CGVector(dx: 10, dy: 10), in: display), in: display)
        }
    }

    @Test(arguments: smallDisplays, FrameHandle.allCases)
    func smallDisplayWinsOverTheFloor(display: CGRect, handle: FrameHandle) {
        let start = FrameGeometry.preset(.center, in: display)
        for delta in [CGVector(dx: 50, dy: 50), CGVector(dx: -50, dy: -50), CGVector(dx: CGFloat.nan, dy: 1e300)] {
            expectValid(FrameGeometry.resize(start, handle: handle, by: delta, in: display), in: display)
        }
    }

    @Test(arguments: FrameHandle.allCases)
    func displayTooSmallForAnyFrameDoesNotTrap(handle: FrameHandle) {
        let result = FrameGeometry.resize(CGRect(x: 10, y: 10, width: 160, height: 90), handle: handle, by: CGVector(dx: 1e300, dy: CGFloat.nan), in: tinyDisplay)
        #expect(result.minX.isFinite && result.minY.isFinite && result.width.isFinite && result.height.isFinite)
    }
}

@Suite struct FrameGeometryMoveSanitizingTests {
    @Test(arguments: TestDisplays.all, hostileNumbers)
    func hostileDeltasKeepTheInvariants(display: CGRect, value: CGFloat) {
        let start = place(startLocal, on: display)
        for delta in [CGVector(dx: value, dy: value), CGVector(dx: value, dy: 0), CGVector(dx: 0, dy: value), CGVector(dx: -value, dy: value)] {
            expectValid(FrameGeometry.move(start, by: delta, in: display), in: display)
        }
    }

    @Test(arguments: TestDisplays.all)
    func nanDeltaChangesNothing(display: CGRect) {
        let start = place(startLocal, on: display)
        #expect(FrameGeometry.move(start, by: CGVector(dx: CGFloat.nan, dy: CGFloat.nan), in: display) == start)
    }

    @Test func hugeDeltaPushesTheFrameToTheDisplayEdge() {
        let display = TestDisplays.main
        let start = place(startLocal, on: display)
        let result = FrameGeometry.move(start, by: CGVector(dx: 1e300, dy: -1e300), in: display)
        #expect(result == CGRect(x: 1800 - 960, y: 0, width: 960, height: 540))
    }

    @Test(arguments: smallDisplays)
    func smallDisplayKeepsTheFrameInside(display: CGRect) {
        let start = FrameGeometry.preset(.center, in: display)
        expectValid(FrameGeometry.move(start, by: CGVector(dx: 1e300, dy: CGFloat.nan), in: display), in: display)
    }
}

@Suite struct FrameGeometryClampSanitizingTests {
    @Test(arguments: TestDisplays.all + smallDisplays, hostileNumbers)
    func nonFiniteRectComponentsKeepTheInvariants(display: CGRect, value: CGFloat) {
        for rect in [
            CGRect(x: value, y: 0, width: 640, height: 360),
            CGRect(x: 0, y: value, width: 640, height: 360),
            CGRect(x: 0, y: 0, width: value, height: 360),
            CGRect(x: 0, y: 0, width: 640, height: value),
            CGRect(x: value, y: value, width: value, height: value),
        ] {
            expectValid(FrameGeometry.clamp(rect, to: display), in: display)
        }
    }

    @Test(arguments: TestDisplays.all)
    func nullAndInfiniteRectsKeepTheInvariants(display: CGRect) {
        expectValid(FrameGeometry.clamp(.null, to: display), in: display)
        expectValid(FrameGeometry.clamp(.infinite, to: display), in: display)
    }

    @Test func nanWidthSnapsToTheFloor() {
        let result = FrameGeometry.clamp(CGRect(x: 100, y: 100, width: CGFloat.nan, height: 360), to: TestDisplays.main)
        #expect(result == CGRect(x: 100, y: 100, width: 640, height: 360))
    }

    @Test func infiniteWidthSnapsToTheLargestFrame() {
        let result = FrameGeometry.clamp(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 360), to: TestDisplays.main)
        #expect(result.size == CGSize(width: 1792, height: 1008))
    }

    @Test(arguments: smallDisplays)
    func displayBelowTheFloorGetsItsLargestFrame(display: CGRect) {
        let result = FrameGeometry.clamp(CGRect(x: 0, y: 0, width: 640, height: 360), to: display)
        #expect(result.width == CGFloat(16 * FrameGeometry.maxK(in: display)))
        expectValid(result, in: display)
    }

    @Test func displayTooSmallForAnyFrameDoesNotTrap() {
        let result = FrameGeometry.clamp(CGRect(x: CGFloat.nan, y: 1e300, width: 1e300, height: CGFloat.nan), to: tinyDisplay)
        #expect(result.width.isFinite && result.height.isFinite)
        #expect(FrameGeometry.maxK(in: tinyDisplay) == 1)
        #expect(FrameGeometry.preset(.center, in: tinyDisplay).width.isFinite)
        #expect(FrameGeometry.restore(local: CGRect(x: 0, y: 0, width: 1e300, height: 5), in: tinyDisplay).width.isFinite)
    }

    @Test(arguments: hostileNumbers)
    func hostileDisplayDoesNotTrap(value: CGFloat) {
        let display = CGRect(x: 0, y: 0, width: value, height: value)
        _ = FrameGeometry.maxK(in: display)
        _ = FrameGeometry.clamp(CGRect(x: 0, y: 0, width: 640, height: 360), to: display)
        _ = FrameGeometry.preset(.center, in: display)
    }
}

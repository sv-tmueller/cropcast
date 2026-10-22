import CoreGraphics
import Testing
@testable import RegionFrame

/// Made-up display frames in AppKit global coordinates (bottom-left origin).
enum TestDisplays {
    static let main = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    static let ultrawide = CGRect(x: -1652, y: 1169, width: 5120, height: 1440)
    static let right = CGRect(x: 1800, y: 0, width: 1920, height: 1080)
    static let negative = CGRect(x: -2000, y: -1200, width: 1600, height: 900)
    static let all = [main, ultrawide, right, negative]
}

/// A rect given in display-local coordinates, placed on `display`.
func place(_ local: CGRect, on display: CGRect) -> CGRect {
    local.offsetBy(dx: display.minX, dy: display.minY)
}

/// Asserts the invariants every geometry result must keep.
func expectValid(_ rect: CGRect, in display: CGRect, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(rect.width * 9 == rect.height * 16, "not exactly 16:9: \(rect)", sourceLocation: sourceLocation)
    #expect(rect.width.truncatingRemainder(dividingBy: 16) == 0, "width not 16k: \(rect)", sourceLocation: sourceLocation)
    #expect(rect.minX == rect.minX.rounded() && rect.minY == rect.minY.rounded(), "origin not whole: \(rect)", sourceLocation: sourceLocation)
    #expect(display.contains(rect), "\(rect) escapes \(display)", sourceLocation: sourceLocation)
}

/// Start rect used by the resize tests: k = 60 (960x540) at local (400, 200).
/// It leaves room on every side of every test display.
let startLocal = CGRect(x: 400, y: 200, width: 960, height: 540)

/// +1 when the handle drags the right/top side, -1 for left/bottom, 0 for none.
func direction(of handle: FrameHandle) -> (x: CGFloat, y: CGFloat) {
    switch handle {
    case .topLeft: (-1, 1)
    case .top: (0, 1)
    case .topRight: (1, 1)
    case .right: (1, 0)
    case .bottomRight: (1, -1)
    case .bottom: (0, -1)
    case .bottomLeft: (-1, -1)
    case .left: (-1, 0)
    }
}

let cornerHandles: [FrameHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
let edgeHandles: [FrameHandle] = [.top, .right, .bottom, .left]

@Suite struct FrameGeometryBoundsTests {
    @Test func maxKIsLimitedByTheTighterAxis() {
        #expect(FrameGeometry.maxK(in: TestDisplays.main) == 112)      // width: 1800/16
        #expect(FrameGeometry.maxK(in: TestDisplays.ultrawide) == 160) // height: 1440/9
        #expect(FrameGeometry.maxK(in: TestDisplays.right) == 120)
    }

    @Test func minimumFrameIs640x360() {
        #expect(FrameGeometry.minK == 40)
    }
}

@Suite struct FrameGeometryClampTests {
    @Test(arguments: TestDisplays.all)
    func oversizedRectShrinksToLargestFit(display: CGRect) {
        let result = FrameGeometry.clamp(CGRect(x: display.minX, y: display.minY, width: 9000, height: 5000), to: display)
        let k = FrameGeometry.maxK(in: display)
        #expect(result.size == CGSize(width: 16 * CGFloat(k), height: 9 * CGFloat(k)))
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func tinyRectGrowsToTheFloor(display: CGRect) {
        let result = FrameGeometry.clamp(place(CGRect(x: 10, y: 10, width: 100, height: 56), on: display), to: display)
        #expect(result.size == CGSize(width: 640, height: 360))
        expectValid(result, in: display)
    }

    @Test func nonSixteenNineSizeSnapsToWidthSteps() {
        let display = TestDisplays.main
        let result = FrameGeometry.clamp(CGRect(x: 10, y: 10, width: 1000, height: 700), to: display)
        #expect(result.size == CGSize(width: 1008, height: 567)) // k = round(1000/16) = 63
        expectValid(result, in: display)
    }

    @Test func rectHangingOffTheEdgeIsShiftedInside() {
        let display = TestDisplays.main
        let result = FrameGeometry.clamp(CGRect(x: 1700, y: 1000, width: 1280, height: 720), to: display)
        #expect(result == CGRect(x: 520, y: 449, width: 1280, height: 720))
    }

    @Test func rectBelowAndLeftOfTheDisplayIsShiftedInside() {
        let display = TestDisplays.negative
        let result = FrameGeometry.clamp(CGRect(x: -9000, y: -9000, width: 640, height: 360), to: display)
        #expect(result == CGRect(x: -2000, y: -1200, width: 640, height: 360))
    }
}

@Suite struct FrameGeometryMoveTests {
    @Test(arguments: TestDisplays.all)
    func moveShiftsByTheRoundedDelta(display: CGRect) {
        let start = place(startLocal, on: display)
        let result = FrameGeometry.move(start, by: CGVector(dx: 50.4, dy: -20.6), in: display)
        #expect(result == start.offsetBy(dx: 50, dy: -21))
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func moveIsClampedAtAllFourEdges(display: CGRect) {
        let start = place(startLocal, on: display)
        let left = FrameGeometry.move(start, by: CGVector(dx: -99999, dy: 0), in: display)
        let right = FrameGeometry.move(start, by: CGVector(dx: 99999, dy: 0), in: display)
        let down = FrameGeometry.move(start, by: CGVector(dx: 0, dy: -99999), in: display)
        let up = FrameGeometry.move(start, by: CGVector(dx: 0, dy: 99999), in: display)
        #expect(left == CGRect(x: display.minX, y: start.minY, width: 960, height: 540))
        #expect(right == CGRect(x: display.maxX - 960, y: start.minY, width: 960, height: 540))
        #expect(down == CGRect(x: start.minX, y: display.minY, width: 960, height: 540))
        #expect(up == CGRect(x: start.minX, y: display.maxY - 540, width: 960, height: 540))
        for result in [left, right, down, up] { expectValid(result, in: display) }
    }
}

@Suite struct FrameGeometryCornerResizeTests {
    /// The corner opposite `handle` must not move.
    func expectFixedCorner(_ result: CGRect, of start: CGRect, handle: FrameHandle, sourceLocation: SourceLocation = #_sourceLocation) {
        let dir = direction(of: handle)
        if dir.x > 0 { #expect(result.minX == start.minX, sourceLocation: sourceLocation) } else { #expect(result.maxX == start.maxX, sourceLocation: sourceLocation) }
        if dir.y > 0 { #expect(result.minY == start.minY, sourceLocation: sourceLocation) } else { #expect(result.maxY == start.maxY, sourceLocation: sourceLocation) }
    }

    @Test(arguments: TestDisplays.all, cornerHandles)
    func horizontalDragGrowsAndShrinks(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)

        let grown = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * 160, dy: 0), in: display)
        #expect(grown.size == CGSize(width: 1120, height: 630))
        expectFixedCorner(grown, of: start, handle: handle)
        expectValid(grown, in: display)

        let shrunk = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * -160, dy: 0), in: display)
        #expect(shrunk.size == CGSize(width: 800, height: 450))
        expectFixedCorner(shrunk, of: start, handle: handle)
        expectValid(shrunk, in: display)
    }

    @Test(arguments: TestDisplays.all, cornerHandles)
    func verticalDragGrowsAndShrinks(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)

        let grown = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: 0, dy: dir.y * 90), in: display)
        #expect(grown.size == CGSize(width: 1120, height: 630))
        expectFixedCorner(grown, of: start, handle: handle)
        expectValid(grown, in: display)

        let shrunk = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: 0, dy: dir.y * -90), in: display)
        #expect(shrunk.size == CGSize(width: 800, height: 450))
        expectFixedCorner(shrunk, of: start, handle: handle)
        expectValid(shrunk, in: display)
    }

    @Test(arguments: TestDisplays.all, cornerHandles)
    func diagonalDragFollowsTheDominantAxis(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)

        // Width wins: |dx|*9 = 1440 >= |dy|*16 = 160.
        let widthWins = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * 160, dy: dir.y * 10), in: display)
        #expect(widthWins.size == CGSize(width: 1120, height: 630))
        expectFixedCorner(widthWins, of: start, handle: handle)
        expectValid(widthWins, in: display)

        // Height wins: |dx|*9 = 144 < |dy|*16 = 1440.
        let heightWins = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * 16, dy: dir.y * 90), in: display)
        #expect(heightWins.size == CGSize(width: 1120, height: 630))
        expectFixedCorner(heightWins, of: start, handle: handle)
        expectValid(heightWins, in: display)
    }

    @Test(arguments: TestDisplays.all, FrameHandle.allCases)
    func dragPastTheFloorStopsAt640x360(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)
        let result = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * -5000, dy: dir.y * -5000), in: display)
        #expect(result.size == CGSize(width: 640, height: 360))
        expectValid(result, in: display)
        if cornerHandles.contains(handle) { expectFixedCorner(result, of: start, handle: handle) }
    }

    @Test(arguments: zip(TestDisplays.all, [87, 137, 95, 75]))
    func dragPastTheDisplayStopsAtTheRoomAroundTheFixedCorner(display: CGRect, expectedK: Int) {
        // Fixed corner is the start's bottom-left at local (400, 200).
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .topRight, by: CGVector(dx: 99999, dy: 99999), in: display)
        #expect(result.width == CGFloat(16 * expectedK))
        #expect(result.origin == start.origin)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all, cornerHandles)
    func hugeDragNeverEscapesTheDisplay(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)
        let result = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * 99999, dy: dir.y * 99999), in: display)
        expectValid(result, in: display)
        expectFixedCorner(result, of: start, handle: handle)
    }
}

@Suite struct FrameGeometryEdgeResizeTests {
    @Test(arguments: TestDisplays.all)
    func rightEdgeKeepsLeftEdgeAndCentresVertically(display: CGRect) {
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .right, by: CGVector(dx: 160, dy: 777), in: display)
        #expect(result.size == CGSize(width: 1120, height: 630)) // dy is ignored
        #expect(result.minX == start.minX)
        #expect(result.midY == start.midY)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func leftEdgeKeepsRightEdgeAndCentresVertically(display: CGRect) {
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .left, by: CGVector(dx: -160, dy: 777), in: display)
        #expect(result.size == CGSize(width: 1120, height: 630))
        #expect(result.maxX == start.maxX)
        #expect(result.midY == start.midY)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func topEdgeKeepsBottomEdgeAndCentresHorizontally(display: CGRect) {
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .top, by: CGVector(dx: 777, dy: 90), in: display)
        #expect(result.size == CGSize(width: 1120, height: 630)) // dx is ignored
        #expect(result.minY == start.minY)
        #expect(result.midX == start.midX)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func bottomEdgeKeepsTopEdgeAndCentresHorizontally(display: CGRect) {
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .bottom, by: CGVector(dx: 777, dy: -90), in: display)
        #expect(result.size == CGSize(width: 1120, height: 630))
        #expect(result.maxY == start.maxY)
        #expect(result.midX == start.midX)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all, edgeHandles)
    func shrinkingKeepsTheFixedEdge(display: CGRect, handle: FrameHandle) {
        let start = place(startLocal, on: display)
        let dir = direction(of: handle)
        let result = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: dir.x * -160, dy: dir.y * -90), in: display)
        #expect(result.size == CGSize(width: 800, height: 450))
        switch handle {
        case .right: #expect(result.minX == start.minX)
        case .left: #expect(result.maxX == start.maxX)
        case .top: #expect(result.minY == start.minY)
        default: #expect(result.maxY == start.maxY)
        }
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func otherAxisIsShiftedBackInsideAtTheBottom(display: CGRect) {
        // Centring the taller frame would push it 45 pt below the display.
        let start = place(CGRect(x: 400, y: 0, width: 960, height: 540), on: display)
        let result = FrameGeometry.resize(start, handle: .right, by: CGVector(dx: 160, dy: 0), in: display)
        #expect(result.size == CGSize(width: 1120, height: 630))
        #expect(result.minY == display.minY)
        #expect(result.minX == start.minX)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func otherAxisIsShiftedBackInsideAtTheTop(display: CGRect) {
        let start = place(CGRect(x: 400, y: display.height - 540, width: 960, height: 540), on: display)
        let result = FrameGeometry.resize(start, handle: .left, by: CGVector(dx: -160, dy: 0), in: display)
        #expect(result.size == CGSize(width: 1120, height: 630))
        #expect(result.maxY == display.maxY)
        #expect(result.maxX == start.maxX)
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all)
    func otherAxisIsShiftedBackInsideAtTheSides(display: CGRect) {
        let atLeft = place(CGRect(x: 0, y: 200, width: 960, height: 540), on: display)
        let fromLeft = FrameGeometry.resize(atLeft, handle: .top, by: CGVector(dx: 0, dy: 90), in: display)
        #expect(fromLeft.minX == display.minX)
        expectValid(fromLeft, in: display)

        let atRight = place(CGRect(x: display.width - 960, y: 200, width: 960, height: 540), on: display)
        let fromRight = FrameGeometry.resize(atRight, handle: .top, by: CGVector(dx: 0, dy: 90), in: display)
        #expect(fromRight.maxX == display.maxX)
        expectValid(fromRight, in: display)
    }

    @Test(arguments: zip(TestDisplays.all, [87, 160, 95, 75]))
    func rightEdgeDragStopsAtTheRoomOrTheDisplayHeight(display: CGRect, expectedK: Int) {
        // Room right of local x=400 limits k, except on the ultrawide where the height does.
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .right, by: CGVector(dx: 99999, dy: 0), in: display)
        #expect(result.width == CGFloat(16 * expectedK))
        #expect(result.minX == start.minX)
        expectValid(result, in: display)
    }

    @Test(arguments: zip(TestDisplays.all, [107, 137, 97, 77]))
    func topEdgeDragStopsAtTheRoomAboveTheBottomEdge(display: CGRect, expectedK: Int) {
        let start = place(startLocal, on: display)
        let result = FrameGeometry.resize(start, handle: .top, by: CGVector(dx: 0, dy: 99999), in: display)
        #expect(result.height == CGFloat(9 * expectedK))
        #expect(result.minY == start.minY)
        expectValid(result, in: display)
    }
}

@Suite struct FrameGeometryPresetTests {
    @Test func ultrawideSlotsAreFullHeight() {
        let display = TestDisplays.ultrawide
        #expect(FrameGeometry.preset(.left, in: display) == CGRect(x: -1652, y: 1169, width: 2560, height: 1440))
        #expect(FrameGeometry.preset(.center, in: display) == CGRect(x: -372, y: 1169, width: 2560, height: 1440))
        #expect(FrameGeometry.preset(.right, in: display) == CGRect(x: 908, y: 1169, width: 2560, height: 1440))
    }

    @Test func sixteenNineDisplayGivesTheFullDisplayForAllPresets() {
        for display in [TestDisplays.right, TestDisplays.negative] {
            for preset in RegionPreset.allCases {
                #expect(FrameGeometry.preset(preset, in: display) == display)
            }
        }
    }

    @Test func mainDisplayCentresVerticallyRoundedDown() {
        let display = TestDisplays.main
        #expect(FrameGeometry.preset(.left, in: display) == CGRect(x: 0, y: 80, width: 1792, height: 1008))
        #expect(FrameGeometry.preset(.center, in: display) == CGRect(x: 4, y: 80, width: 1792, height: 1008))
        #expect(FrameGeometry.preset(.right, in: display) == CGRect(x: 8, y: 80, width: 1792, height: 1008))
    }

    @Test(arguments: TestDisplays.all, RegionPreset.allCases)
    func presetsAreValid(display: CGRect, preset: RegionPreset) {
        expectValid(FrameGeometry.preset(preset, in: display), in: display)
    }
}

@Suite struct FrameGeometryRestoreTests {
    @Test(arguments: TestDisplays.all)
    func nothingStoredFallsBackToTheCentrePreset(display: CGRect) {
        #expect(FrameGeometry.restore(local: nil, in: display) == FrameGeometry.preset(.center, in: display))
    }

    @Test func storedLocalRectFollowsAMovedDisplayOrigin() {
        let stored = CGRect(x: 100, y: 50, width: 1280, height: 720)
        #expect(FrameGeometry.restore(local: stored, in: TestDisplays.right) == CGRect(x: 1900, y: 50, width: 1280, height: 720))
        #expect(FrameGeometry.restore(local: stored, in: TestDisplays.negative) == CGRect(x: -1900, y: -1150, width: 1280, height: 720))
    }

    @Test func oversizedStoredRectIsClamped() {
        let result = FrameGeometry.restore(local: CGRect(x: 0, y: 0, width: 9000, height: 5000), in: TestDisplays.main)
        #expect(result == CGRect(x: 0, y: 0, width: 1792, height: 1008))
    }

    @Test func storedRectOutsideTheDisplayIsShiftedInside() {
        let result = FrameGeometry.restore(local: CGRect(x: 1700, y: 1000, width: 1280, height: 720), in: TestDisplays.main)
        #expect(result == CGRect(x: 520, y: 449, width: 1280, height: 720))
    }
}

@Suite struct FrameGeometryResizeStartRectTests {
    @Test func startRectHangingOffTheEdgeStillKeepsTheMinimumSize() {
        let display = TestDisplays.main
        let start = CGRect(x: 1500, y: 0, width: 640, height: 360)
        let result = FrameGeometry.resize(start, handle: .topRight, by: CGVector(dx: 10, dy: 10), in: display)
        #expect(result.width >= 640 && result.height >= 360, "\(result)")
        expectValid(result, in: display)
    }

    @Test(arguments: TestDisplays.all, FrameHandle.allCases)
    func fractionalStartRectGivesWholeOrigins(display: CGRect, handle: FrameHandle) {
        let start = CGRect(x: display.minX + 100.5, y: display.minY + 200.5, width: 960, height: 540)
        let result = FrameGeometry.resize(start, handle: handle, by: CGVector(dx: 16, dy: 9), in: display)
        expectValid(result, in: display)
    }
}

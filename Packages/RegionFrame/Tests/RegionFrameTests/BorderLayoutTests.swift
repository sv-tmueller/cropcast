import CoreGraphics
import Testing
@testable import RegionFrame

@Suite struct BorderLayoutTests {
    static let frames = [
        CGRect(x: 100, y: 200, width: 1280, height: 720),
        CGRect(x: -1652, y: 1169, width: 2560, height: 1440),
        CGRect(x: -2000, y: -1200, width: 640, height: 360), // the floor size
    ]
    let metrics = BorderMetrics.standard

    /// Grid of points covering `rect`, boundaries included.
    func grid(over rect: CGRect, step: CGFloat) -> [CGPoint] {
        func axis(_ low: CGFloat, _ high: CGFloat) -> [CGFloat] {
            var values = Array(stride(from: low, through: high, by: step))
            if values.last != high { values.append(high) }
            return values
        }
        let ys = axis(rect.minY, rect.maxY)
        return axis(rect.minX, rect.maxX).flatMap { x in ys.map { CGPoint(x: x, y: $0) } }
    }

    @Test(arguments: frames)
    func stripsStayInsideTheFrame(frame: CGRect) {
        for edge in BorderEdge.allCases {
            let strip = BorderLayout.strip(for: edge, in: frame, metrics: metrics)
            #expect(frame.contains(strip), "\(edge) strip \(strip) escapes \(frame)")
            #expect(!strip.isEmpty)
        }
    }

    @Test(arguments: frames)
    func stripsDoNotOverlapAndTileTheBand(frame: CGRect) {
        let strips = BorderEdge.allCases.map { BorderLayout.strip(for: $0, in: frame, metrics: metrics) }
        for i in strips.indices {
            for j in strips.indices where j > i {
                let overlap = strips[i].intersection(strips[j])
                #expect(overlap.isNull || overlap.isEmpty, "strips \(i) and \(j) overlap")
            }
        }
        let t = metrics.thickness
        let bandArea = frame.width * frame.height - (frame.width - 2 * t) * (frame.height - 2 * t)
        #expect(strips.reduce(0) { $0 + $1.width * $1.height } == bandArea)
    }

    @Test(arguments: frames)
    func everyPointInsideTheBandIsClickThrough(frame: CGRect) {
        let interior = frame.insetBy(dx: metrics.thickness, dy: metrics.thickness)
        for point in grid(over: interior, step: 7) {
            #expect(BorderLayout.zone(at: point, in: frame, metrics: metrics) == nil, "\(point) should pass clicks through")
        }
    }

    @Test(arguments: frames)
    func pointsOutsideTheFrameAreNotHit(frame: CGRect) {
        for point in [
            CGPoint(x: frame.minX - 1, y: frame.midY), CGPoint(x: frame.maxX + 1, y: frame.midY),
            CGPoint(x: frame.midX, y: frame.minY - 1), CGPoint(x: frame.midX, y: frame.maxY + 1),
        ] {
            #expect(BorderLayout.zone(at: point, in: frame, metrics: metrics) == nil)
        }
    }

    @Test(arguments: frames)
    func cornersMapToCornerHandles(frame: CGRect) {
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .resize(.topLeft))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.maxX - 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .resize(.topRight))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.maxX - 1, y: frame.minY + 1), in: frame, metrics: metrics) == .resize(.bottomRight))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + 1, y: frame.minY + 1), in: frame, metrics: metrics) == .resize(.bottomLeft))
    }

    @Test(arguments: frames)
    func cornerHandleIsAnLShapedBracket(frame: CGRect) {
        let arm = metrics.cornerArm
        // Along the top band and the left band, within the arm length: corner.
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + arm - 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .resize(.topLeft))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + 1, y: frame.maxY - arm + 1), in: frame, metrics: metrics) == .resize(.topLeft))
        // Past the arm: the rest of the band moves the frame.
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + arm + 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .move)
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + 1, y: frame.maxY - arm - 1), in: frame, metrics: metrics) == .move)
        // Inside the bracket's bounding square but off the band: click-through.
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + arm - 1, y: frame.maxY - arm + 1), in: frame, metrics: metrics) == nil)
    }

    @Test(arguments: frames)
    func edgeMidpointsMapToEdgeHandles(frame: CGRect) {
        #expect(BorderLayout.zone(at: CGPoint(x: frame.midX, y: frame.maxY - 1), in: frame, metrics: metrics) == .resize(.top))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.midX, y: frame.minY + 1), in: frame, metrics: metrics) == .resize(.bottom))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + 1, y: frame.midY), in: frame, metrics: metrics) == .resize(.left))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.maxX - 1, y: frame.midY), in: frame, metrics: metrics) == .resize(.right))
    }

    @Test(arguments: frames)
    func edgeHandleHasALimitedLength(frame: CGRect) {
        let half = metrics.edgeHandleLength / 2
        #expect(BorderLayout.zone(at: CGPoint(x: frame.midX + half - 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .resize(.top))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.midX - half + 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .resize(.top))
        #expect(BorderLayout.zone(at: CGPoint(x: frame.midX + half + 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .move)
        #expect(BorderLayout.zone(at: CGPoint(x: frame.midX - half - 1, y: frame.maxY - 1), in: frame, metrics: metrics) == .move)
    }

    @Test(arguments: frames)
    func restOfTheBandMovesTheFrame(frame: CGRect) {
        let quarterX = frame.minX + frame.width / 4
        let quarterY = frame.minY + frame.height / 4
        #expect(BorderLayout.zone(at: CGPoint(x: quarterX, y: frame.maxY - 1), in: frame, metrics: metrics) == .move)
        #expect(BorderLayout.zone(at: CGPoint(x: quarterX, y: frame.minY + 1), in: frame, metrics: metrics) == .move)
        #expect(BorderLayout.zone(at: CGPoint(x: frame.minX + 1, y: quarterY), in: frame, metrics: metrics) == .move)
        #expect(BorderLayout.zone(at: CGPoint(x: frame.maxX - 1, y: quarterY), in: frame, metrics: metrics) == .move)
    }

    @Test(arguments: frames)
    func handleRectsAgreeWithZones(frame: CGRect) {
        for handle in FrameHandle.allCases {
            let rects = BorderLayout.handleRects(for: handle, in: frame, metrics: metrics)
            #expect(!rects.isEmpty)
            for rect in rects {
                #expect(frame.contains(rect))
                for point in grid(over: rect.insetBy(dx: 0.5, dy: 0.5), step: 3) {
                    #expect(BorderLayout.zone(at: point, in: frame, metrics: metrics) == .resize(handle), "\(point) in \(handle) rect")
                }
            }
        }
    }

    @Test func cornerAndEdgeHandlesDoNotOverlapOnTheSmallestFrame() {
        let frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        let corner = BorderLayout.handleRects(for: .topLeft, in: frame, metrics: metrics)
        let edge = BorderLayout.handleRects(for: .top, in: frame, metrics: metrics)
        for c in corner {
            for e in edge {
                let overlap = c.intersection(e)
                #expect(overlap.isNull || overlap.isEmpty)
            }
        }
    }
}

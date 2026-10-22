import CoreGraphics

/// Sizes of the frame border. The border is a band *inside* the region rect, so
/// the interior is never covered by a window and clicks always reach the app below.
struct BorderMetrics: Equatable, Sendable {
    /// Thickness of the band in points.
    var thickness: CGFloat
    /// Length of each arm of an L-shaped corner bracket, measured from the corner.
    var cornerArm: CGFloat
    /// Length of the edge handle bar, centred on the edge's midpoint.
    var edgeHandleLength: CGFloat

    static let standard = BorderMetrics(thickness: 8, cornerArm: 36, edgeHandleLength: 72)
}

enum BorderEdge: CaseIterable, Sendable {
    case top, bottom, left, right
}

/// What a point on the border does when dragged.
enum BorderZone: Equatable, Sendable {
    case move
    case resize(FrameHandle)
}

/// Pure layout of the four border strips and the hit zones inside them.
/// All rects are in the same (AppKit global) coordinates as `frame`.
enum BorderLayout {
    /// The strip along `edge`, inside `frame`. Top and bottom run the full width;
    /// left and right fill the space between them, so the strips never overlap.
    static func strip(for edge: BorderEdge, in frame: CGRect, metrics: BorderMetrics = .standard) -> CGRect {
        let t = metrics.thickness
        switch edge {
        case .top: return CGRect(x: frame.minX, y: frame.maxY - t, width: frame.width, height: t)
        case .bottom: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: t)
        case .left: return CGRect(x: frame.minX, y: frame.minY + t, width: t, height: frame.height - 2 * t)
        case .right: return CGRect(x: frame.maxX - t, y: frame.minY + t, width: t, height: frame.height - 2 * t)
        }
    }

    /// The rects that make up `handle`: two arms for a corner, one bar for an edge.
    static func handleRects(for handle: FrameHandle, in frame: CGRect, metrics: BorderMetrics = .standard) -> [CGRect] {
        let t = metrics.thickness
        let arm = metrics.cornerArm
        let len = metrics.edgeHandleLength
        switch handle {
        case .topLeft:
            return [CGRect(x: frame.minX, y: frame.maxY - t, width: arm, height: t),
                    CGRect(x: frame.minX, y: frame.maxY - arm, width: t, height: arm)]
        case .topRight:
            return [CGRect(x: frame.maxX - arm, y: frame.maxY - t, width: arm, height: t),
                    CGRect(x: frame.maxX - t, y: frame.maxY - arm, width: t, height: arm)]
        case .bottomLeft:
            return [CGRect(x: frame.minX, y: frame.minY, width: arm, height: t),
                    CGRect(x: frame.minX, y: frame.minY, width: t, height: arm)]
        case .bottomRight:
            return [CGRect(x: frame.maxX - arm, y: frame.minY, width: arm, height: t),
                    CGRect(x: frame.maxX - t, y: frame.minY, width: t, height: arm)]
        case .top:
            return [CGRect(x: frame.midX - len / 2, y: frame.maxY - t, width: len, height: t)]
        case .bottom:
            return [CGRect(x: frame.midX - len / 2, y: frame.minY, width: len, height: t)]
        case .left:
            return [CGRect(x: frame.minX, y: frame.midY - len / 2, width: t, height: len)]
        case .right:
            return [CGRect(x: frame.maxX - t, y: frame.midY - len / 2, width: t, height: len)]
        }
    }

    /// The zone under `point`, or nil when the point is not on the border band
    /// (outside the frame or in its click-through interior).
    static func zone(at point: CGPoint, in frame: CGRect, metrics: BorderMetrics = .standard) -> BorderZone? {
        guard point.x >= frame.minX, point.x <= frame.maxX, point.y >= frame.minY, point.y <= frame.maxY else { return nil }
        let t = metrics.thickness
        let inTop = point.y > frame.maxY - t
        let inBottom = point.y < frame.minY + t
        let inLeft = point.x < frame.minX + t
        let inRight = point.x > frame.maxX - t
        guard inTop || inBottom || inLeft || inRight else { return nil }

        // Corner brackets: the band within `cornerArm` of a corner on both axes.
        let arm = metrics.cornerArm
        let nearLeft = point.x < frame.minX + arm
        let nearRight = point.x > frame.maxX - arm
        let nearTop = point.y > frame.maxY - arm
        let nearBottom = point.y < frame.minY + arm
        if nearTop && nearLeft { return .resize(.topLeft) }
        if nearTop && nearRight { return .resize(.topRight) }
        if nearBottom && nearLeft { return .resize(.bottomLeft) }
        if nearBottom && nearRight { return .resize(.bottomRight) }

        // Edge bars at each edge's midpoint.
        let half = metrics.edgeHandleLength / 2
        let alongX = point.x >= frame.midX - half && point.x < frame.midX + half
        let alongY = point.y >= frame.midY - half && point.y < frame.midY + half
        if inTop && alongX { return .resize(.top) }
        if inBottom && alongX { return .resize(.bottom) }
        if inLeft && alongY { return .resize(.left) }
        if inRight && alongY { return .resize(.right) }

        return .move
    }
}

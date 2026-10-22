import CoreGraphics

/// Pure placement math for the virtual display, in CoreGraphics global
/// coordinates (top-left origin, y grows downward).
enum Placement {
    /// Origin that puts a display of `displaySize` diagonally against the
    /// bottom-left corner of the main display, so the two touch only at that
    /// corner point. The top corners are avoided because users aim for the menu
    /// bar there, and the bottom-right is the default Quick Note hot corner.
    static func origin(mainBounds: CGRect, displaySize: CGSize) -> CGPoint {
        CGPoint(x: mainBounds.minX - displaySize.width, y: mainBounds.maxY)
    }
}

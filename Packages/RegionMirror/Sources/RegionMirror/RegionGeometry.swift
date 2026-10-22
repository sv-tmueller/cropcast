import CoreGraphics

/// Pure coordinate conversion between AppKit and ScreenCaptureKit spaces.
public enum RegionGeometry {
    /// Converts a region in AppKit global coordinates (points, bottom-left
    /// origin) into a display-local, top-left-origin rect in points, which is
    /// what `SCStreamConfiguration.sourceRect` expects.
    ///
    /// - Parameters:
    ///   - region: The region in AppKit global coordinates.
    ///   - displayFrame: The display's `NSScreen.frame` (AppKit global coordinates).
    /// - Returns: The rect clipped to the display, or `nil` if the region has
    ///   no overlap with the display.
    public static func captureSourceRect(
        forAppKitRegion region: CGRect, displayFrame: CGRect
    ) -> CGRect? {
        let local = CGRect(
            x: region.minX - displayFrame.minX,
            y: displayFrame.maxY - region.maxY,
            width: region.width,
            height: region.height)
        let bounds = CGRect(origin: .zero, size: displayFrame.size)
        let clipped = local.intersection(bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }
}

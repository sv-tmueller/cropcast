import CoreGraphics

/// A connected display as the app glue describes it to the pure choice logic.
public struct DisplayCandidate: Sendable, Equatable {
    public var id: UInt32
    /// Stable identity across launches (the display UUID string).
    public var key: String
    /// `NSScreen.frame.width`.
    public var width: Double

    public init(id: UInt32, key: String, width: Double) {
        self.id = id
        self.key = key
        self.width = width
    }
}

/// Which physical display CropCast captures from.
public enum SourceDisplayChoice {
    /// The last used display if it is still connected, else the widest one
    /// (a width tie goes to the first listed). `excluding` (the virtual
    /// display) is never chosen. Returns nil if nothing is left.
    public static func pick(
        from displays: [DisplayCandidate], excluding: UInt32?, lastUsedKey: String?
    ) -> UInt32? {
        let candidates = displays.filter { $0.id != excluding }
        if let lastUsedKey, let match = candidates.first(where: { $0.key == lastUsedKey }) {
            return match.id
        }
        var widest: DisplayCandidate?
        for candidate in candidates where candidate.width > (widest?.width ?? -.infinity) {
            widest = candidate
        }
        return widest?.id
    }
}

/// CoreGraphics (top-left origin) to AppKit (bottom-left origin) conversion.
public enum ScreenCoordinates {
    /// The AppKit frame of a display whose `CGDisplayBounds` are given.
    /// `primaryHeight` is the height of the primary display
    /// (`CGDisplayBounds(CGMainDisplayID())`).
    public static func appKitFrame(forDisplayBounds bounds: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: bounds.minX, y: primaryHeight - bounds.maxY,
            width: bounds.width, height: bounds.height)
    }

    /// True once `NSScreen` reports the same geometry CoreGraphics does, i.e.
    /// AppKit has caught up with a freshly created display.
    public static func isSettled(
        screenFrame: CGRect?, displayBounds: CGRect, primaryHeight: CGFloat
    ) -> Bool {
        guard let screenFrame else { return false }
        return screenFrame == appKitFrame(forDisplayBounds: displayBounds, primaryHeight: primaryHeight)
    }
}

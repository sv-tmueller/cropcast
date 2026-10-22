import CoreGraphics
import CoreMedia
import ScreenCaptureKit

/// Output settings for a capture stream.
///
/// `SCStream.updateConfiguration(_:)` replaces the whole configuration, and a
/// bare `SCStreamConfiguration()` resets the stream to 1920x1080. Always build
/// configurations through ``makeConfiguration(sourceRect:)``, including on
/// every region update.
public struct CaptureSettings: Sendable, Equatable {
    /// Output width in pixels.
    public var width: Int
    /// Output height in pixels.
    public var height: Int
    /// Maximum frame rate.
    public var framesPerSecond: Int
    /// Whether the cursor is part of the captured frames.
    public var showsCursor: Bool

    public init(
        width: Int = 2560, height: Int = 1440, framesPerSecond: Int = 60, showsCursor: Bool = true
    ) {
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
        self.showsCursor = showsCursor
    }

    /// Builds a complete stream configuration for the given display-local,
    /// top-left-origin source rect (points).
    public func makeConfiguration(sourceRect: CGRect) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        config.showsCursor = showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 5
        return config
    }
}

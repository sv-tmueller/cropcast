import CoreGraphics
import CoreMedia
import ScreenCaptureKit
import Testing

@testable import RegionMirror

@Suite("CaptureSettings.makeConfiguration")
struct CaptureSettingsTests {
    private let sourceRect = CGRect(x: 1280, y: 0, width: 2560, height: 1440)

    @Test("defaults are 2560x1440 at 60 fps with cursor, BGRA")
    func defaults() {
        let settings = CaptureSettings()
        #expect(settings.width == 2560)
        #expect(settings.height == 1440)
        #expect(settings.framesPerSecond == 60)
        #expect(settings.showsCursor)
    }

    @Test("configuration carries output size, never the 1920x1080 default")
    func outputSize() {
        let config = CaptureSettings().makeConfiguration(sourceRect: sourceRect)
        #expect(config.width == 2560)
        #expect(config.height == 1440)
    }

    @Test("configuration sets 60 fps minimum frame interval")
    func frameInterval() {
        let config = CaptureSettings().makeConfiguration(sourceRect: sourceRect)
        #expect(config.minimumFrameInterval == CMTime(value: 1, timescale: 60))
    }

    @Test("configuration shows the cursor")
    func showsCursor() {
        let config = CaptureSettings().makeConfiguration(sourceRect: sourceRect)
        #expect(config.showsCursor)
    }

    @Test("configuration sets the source rect")
    func sourceRectIsSet() {
        let config = CaptureSettings().makeConfiguration(sourceRect: sourceRect)
        #expect(config.sourceRect == sourceRect)
    }

    @Test("configuration uses BGRA pixels")
    func pixelFormat() {
        let config = CaptureSettings().makeConfiguration(sourceRect: sourceRect)
        #expect(config.pixelFormat == kCVPixelFormatType_32BGRA)
    }

    @Test("configuration keeps the SDK default queue depth")
    func queueDepth() {
        let config = CaptureSettings().makeConfiguration(sourceRect: sourceRect)
        #expect(config.queueDepth == SCStreamConfiguration().queueDepth)
    }

    @Test("custom settings are honoured")
    func customSettings() {
        let settings = CaptureSettings(width: 1920, height: 1080, framesPerSecond: 30, showsCursor: false)
        let config = settings.makeConfiguration(sourceRect: sourceRect)
        #expect(config.width == 1920)
        #expect(config.height == 1080)
        #expect(config.minimumFrameInterval == CMTime(value: 1, timescale: 30))
        #expect(!config.showsCursor)
    }
}

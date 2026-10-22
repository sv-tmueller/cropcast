import AVFoundation
import AppKit

/// A layer-backed view that renders sample buffers with an
/// `AVSampleBufferDisplayLayer`. Content is scaled with aspect fill on a
/// black background.
@MainActor
public final class MirrorView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()

    /// The renderer that frames are enqueued into.
    public var videoRenderer: AVSampleBufferVideoRenderer {
        displayLayer.sampleBufferRenderer
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    private func configureLayer() {
        wantsLayer = true
        layer = displayLayer
        displayLayer.videoGravity = .resizeAspectFill
        displayLayer.backgroundColor = NSColor.black.cgColor
    }
}

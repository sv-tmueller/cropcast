import AVFoundation
import CoreMedia
import ScreenCaptureKit
import os

/// Receives frames and stop notifications from ScreenCaptureKit.
///
/// This type is deliberately not `@MainActor`: ScreenCaptureKit calls it on
/// `sampleHandlerQueue`, a private serial queue. It only touches the renderer
/// (thread-safe) and lock-protected state. Results reach the main actor through
/// the `@Sendable` `onStop` closure.
final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sampleHandlerQueue = DispatchQueue(label: "cropcast.regionmirror.samples")

    private struct State {
        var deliveredFrames = 0
        var onStop: (@Sendable (RegionMirrorError) -> Void)?
    }

    private let renderer: AVSampleBufferVideoRenderer
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(
        renderer: AVSampleBufferVideoRenderer,
        onStop: @escaping @Sendable (RegionMirrorError) -> Void
    ) {
        self.renderer = renderer
        state.withLock { $0.onStop = onStop }
        super.init()
    }

    /// Complete frames enqueued into the renderer so far.
    var deliveredFrameCount: Int {
        state.withLock { $0.deliveredFrames }
    }

    /// Stops reporting stream stops, used before an explicit `stopCapture()`.
    func detach() {
        state.withLock { $0.onStop = nil }
    }

    // MARK: SCStreamOutput

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard Self.isCompleteFrame(sampleBuffer) else { return }

        if renderer.status == .failed {
            renderer.flush()
        }
        guard renderer.isReadyForMoreMediaData else { return }

        Self.markDisplayImmediately(sampleBuffer)
        renderer.enqueue(sampleBuffer)
        state.withLock { $0.deliveredFrames += 1 }
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let handler = state.withLock { state in
            let handler = state.onStop
            state.onStop = nil
            return handler
        }
        handler?(RegionMirrorError(captureError: error))
    }

    // MARK: Helpers

    /// Only frames with status `.complete` carry a pixel buffer worth rendering;
    /// idle, blank and suspended notifications are skipped.
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let first = attachments.first,
            let rawStatus = first[.status] as? Int,
            let status = SCFrameStatus(rawValue: rawStatus)
        else { return false }
        return status == .complete
    }

    private static func markDisplayImmediately(_ sampleBuffer: CMSampleBuffer) {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: true),
            CFArrayGetCount(attachments) > 0
        else { return }
        let dictionary = unsafeBitCast(
            CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dictionary,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }
}

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
///
/// The lock is never held while calling the renderer or the logger, so a stuck
/// renderer cannot also block the watchdog that reads the counters.
final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let sampleHandlerQueue = DispatchQueue(label: "cropcast.regionmirror.samples")

    private struct State {
        var counters = FrameCounters()
        var callbackEnteredAt: SuspendingClock.Instant?
        var lastFlushError: String?
        var onStop: (@Sendable (RegionMirrorError) -> Void)?
    }

    private let renderer: AVSampleBufferVideoRenderer
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let clock = SuspendingClock()
    private let watchdog: FrameFlowWatchdog

    init(
        renderer: AVSampleBufferVideoRenderer,
        onStop: @escaping @Sendable (RegionMirrorError) -> Void
    ) {
        self.renderer = renderer
        self.watchdog = FrameFlowWatchdog(renderer: renderer)
        state.withLock { $0.onStop = onStop }
        super.init()
    }

    /// Complete frames enqueued into the renderer so far.
    var deliveredFrameCount: Int {
        state.withLock { $0.counters.enqueued }
    }

    /// Logs the start line and starts the frame-flow watchdog. Call once the
    /// capture is committed as running.
    func captureStarted(_ info: CaptureStartInfo) {
        watchdog.start(info) { [weak self] in self?.flowSample() }
    }

    /// Stops reporting stream stops, used before an explicit `stopCapture()`.
    func detach() {
        let total = state.withLock { state in
            state.onStop = nil
            return state.counters
        }
        watchdog.stop(.requested, total: total)
    }

    fileprivate func flowSample() -> FrameFlowSample {
        state.withLock {
            FrameFlowSample(
                counters: $0.counters, callbackEnteredAt: $0.callbackEnteredAt,
                lastFlushError: $0.lastFlushError)
        }
    }

    // MARK: SCStreamOutput

    func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Entry is visible to the watchdog while the callback runs; the counts
        // are recorded once, at exit, so every window stays consistent.
        let entered = clock.now
        state.withLock { $0.callbackEnteredAt = entered }
        let bucket = FrameStatusBucket(rawStatus: Self.rawStatus(of: sampleBuffer))
        var outcome = FrameOutcome.notComplete
        defer {
            let recorded = outcome
            state.withLock {
                $0.counters.record(bucket, recorded)
                $0.callbackEnteredAt = nil
            }
        }
        guard bucket == .complete else { return }

        if renderer.status == .failed {
            // flush() probably clears the error, so capture it first.
            let errorText = renderer.error.map { FrameFlowWatchdog.describe($0).text }
            renderer.flush()
            state.withLock {
                $0.counters.recordFlush()
                $0.lastFlushError = errorText
            }
        }
        guard renderer.isReadyForMoreMediaData else {
            outcome = .droppedNotReady
            return
        }

        Self.markDisplayImmediately(sampleBuffer)
        renderer.enqueue(sampleBuffer)
        outcome = .enqueued
    }

    // MARK: SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let (handler, total) = state.withLock { state in
            let handler = state.onStop
            state.onStop = nil
            return (handler, state.counters)
        }
        // Logged synchronously, before the handler: a caller may exit the process in it.
        let details = FrameFlowWatchdog.describe(error)
        watchdog.stop(
            .ended(domain: details.domain, code: details.code, description: details.description),
            total: total)
        handler?(RegionMirrorError(captureError: error))
    }

    // MARK: Helpers

    /// The raw `SCFrameStatus` of the sample, nil when unreadable.
    private static func rawStatus(of sampleBuffer: CMSampleBuffer) -> Int? {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
            let first = attachments.first
        else { return nil }
        return first[.status] as? Int
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

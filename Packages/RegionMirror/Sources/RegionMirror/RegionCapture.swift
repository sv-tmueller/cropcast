import AVFoundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures a region of one display with ScreenCaptureKit and feeds the frames
/// into an `AVSampleBufferVideoRenderer`.
///
/// Regions are always in AppKit global coordinates (points, bottom-left
/// origin). CropCast's own app is excluded from capture, so a mirror window on
/// the capture display never shows up in the stream. Show that window before
/// calling ``start(region:renderer:)``.
///
/// Lifecycle: `start` and `stop` are serialized by a `CaptureLifecycle`, so the
/// main actor re-entering during an `await` cannot leave two streams or a
/// stale one behind. A second `start` while starting or running throws
/// ``RegionMirrorError/alreadyRunning`` (it never restarts); `stop()` during a
/// start cancels that start, which stops its own stream and throws
/// ``RegionMirrorError/notRunning``.
///
/// The class never requests Screen Recording permission; it only checks it.
@MainActor
public final class RegionCapture {
    /// What a running capture owns and `tearDown` releases.
    private struct ActiveStream {
        let stream: SCStream
        let output: StreamOutput
    }

    private let sourceDisplayID: CGDirectDisplayID
    private let settings: CaptureSettings
    private var lifecycle = CaptureLifecycle<ActiveStream>()
    private var extraExcludedWindowIDs: [CGWindowID] = []

    /// Called once when the stream stops by itself (not via ``stop()``).
    public var onStop: ((RegionMirrorError) -> Void)?

    /// Complete frames enqueued into the renderer since the last ``start(region:renderer:)``.
    public var deliveredFrameCount: Int { lifecycle.runningStream?.output.deliveredFrameCount ?? 0 }

    public init(sourceDisplayID: CGDirectDisplayID, settings: CaptureSettings = .init()) {
        self.sourceDisplayID = sourceDisplayID
        self.settings = settings
    }

    /// Starts capturing `region` and rendering into `renderer`.
    ///
    /// Calls to ``updateRegion(_:)`` and ``excludeWindows(_:)`` made while this
    /// is in flight are applied before it returns.
    /// - Throws: only ``RegionMirrorError``: ``RegionMirrorError/alreadyRunning``
    ///   when a capture is starting or running, ``RegionMirrorError/notRunning``
    ///   when ``stop()`` cancelled this start.
    public func start(region: CGRect, renderer: AVSampleBufferVideoRenderer) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw RegionMirrorError.permissionDenied }
        guard let token = lifecycle.beginStart() else { throw RegionMirrorError.alreadyRunning }

        // Set before the first fallible stream call, so every failure or
        // cancellation after it tears this stream (and only this one) down.
        var created: ActiveStream?
        do {
            let sourceRect = try sourceRect(for: region)
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            guard lifecycle.isCurrent(token) else { throw RegionMirrorError.notRunning }

            let display = try display(in: content)
            // MainActor reentrancy: excludeWindows(_:) can run during the awaits
            // below. Remember what the filter was built from and re-apply it
            // before committing if the ids changed.
            var appliedExtraWindowIDs = extraExcludedWindowIDs
            let filter = makeFilter(display: display, content: content)
            let configuration = settings.makeConfiguration(sourceRect: sourceRect)

            let output = StreamOutput(renderer: renderer) { [weak self] error in
                Task { @MainActor in self?.streamStopped(token, with: error) }
            }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
            let active = ActiveStream(stream: stream, output: output)
            created = active
            try stream.addStreamOutput(
                output, type: .screen, sampleHandlerQueue: output.sampleHandlerQueue)
            try await stream.startCapture()

            // Settle: apply what changed during the awaits above. Every pass
            // re-checks the token; the pass that finds nothing to do commits
            // with no await in between.
            while true {
                guard lifecycle.isCurrent(token) else { throw RegionMirrorError.notRunning }
                if let pending = lifecycle.takePendingRegion(token) {
                    // updateConfiguration replaces the whole configuration.
                    try await stream.updateConfiguration(
                        settings.makeConfiguration(sourceRect: pending))
                } else if extraExcludedWindowIDs != appliedExtraWindowIDs {
                    appliedExtraWindowIDs = extraExcludedWindowIDs
                    try await updateContentFilter(of: stream)
                } else {
                    break
                }
            }
            guard lifecycle.commit(token, stream: active) else {
                throw RegionMirrorError.notRunning
            }
        } catch {
            if let created { await tearDown(created) }
            lifecycle.startFailed(token)
            throw RegionMirrorError(captureError: error)
        }
    }

    /// Moves the captured region on the same display, keeping the stream running.
    ///
    /// While ``start(region:renderer:)`` is in flight the region is validated
    /// and stored, and this returns before it is applied; the start applies it
    /// before it returns (the latest region wins).
    /// - Throws: ``RegionMirrorError/notRunning``, ``RegionMirrorError/regionOutsideDisplay``
    ///   or a mapped capture error.
    public func updateRegion(_ region: CGRect) async throws {
        if case .idle = lifecycle.phase { throw RegionMirrorError.notRunning }
        let sourceRect = try sourceRect(for: region)
        switch lifecycle.regionUpdate(sourceRect) {
        case .notRunning:
            throw RegionMirrorError.notRunning
        case .deferred:
            return
        case .apply(let active):
            do {
                // updateConfiguration replaces the whole configuration, so always
                // send a complete one.
                try await active.stream.updateConfiguration(
                    settings.makeConfiguration(sourceRect: sourceRect))
            } catch {
                throw RegionMirrorError(captureError: error)
            }
        }
    }

    /// Additionally excludes windows (by `CGWindowID`) from capture. All windows
    /// of this app are always excluded. Stored before or while
    /// ``start(region:renderer:)`` runs (the start applies them before it
    /// returns) and applied live afterwards.
    public func excludeWindows(_ ids: [CGWindowID]) async throws {
        extraExcludedWindowIDs = ids
        guard let active = lifecycle.runningStream else { return }
        do {
            try await updateContentFilter(of: active.stream)
        } catch {
            throw RegionMirrorError(captureError: error)
        }
    }

    /// Stops capturing. Safe to call when not running. A start in flight is
    /// cancelled: it stops its own stream and throws ``RegionMirrorError/notRunning``.
    /// Once both this and the cancelled `start` have returned, no stream exists.
    public func stop() async {
        guard let active = lifecycle.stop() else { return }
        await tearDown(active)
    }

    // MARK: Private

    /// Reports a stream that ended by itself, only if it is still the current one.
    private func streamStopped(_ token: CaptureToken, with error: RegionMirrorError) {
        guard lifecycle.streamEnded(token) else { return }
        onStop?(error)
    }

    /// Detaches the output first so tearing down never reports through `onStop`.
    private func tearDown(_ active: ActiveStream) async {
        active.output.detach()
        try? await active.stream.stopCapture()
        try? active.stream.removeStreamOutput(active.output, type: .screen)
    }

    private func updateContentFilter(of stream: SCStream) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        let display = try display(in: content)
        try await stream.updateContentFilter(makeFilter(display: display, content: content))
    }

    private func sourceRect(for region: CGRect) throws -> CGRect {
        guard let screen = ScreenLookup.screen(for: sourceDisplayID) else {
            throw RegionMirrorError.displayNotFound(sourceDisplayID)
        }
        guard
            let rect = RegionGeometry.captureSourceRect(
                forAppKitRegion: region, displayFrame: screen.frame)
        else { throw RegionMirrorError.regionOutsideDisplay }
        return rect
    }

    private func display(in content: SCShareableContent) throws -> SCDisplay {
        guard let display = content.displays.first(where: { $0.displayID == sourceDisplayID })
        else { throw RegionMirrorError.displayNotFound(sourceDisplayID) }
        return display
    }

    /// Builds the filter from ``ContentFilterPlan``: the whole app is excluded
    /// whenever it is listed in the shareable content (so windows created later
    /// are excluded too), and extra windows owned by other apps are hidden via
    /// `exceptingWindows`.
    private func makeFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let pid = getpid()
        let plan = ContentFilterPlan.make(
            ownProcessID: pid,
            selfApp: content.applications.first { $0.processID == pid },
            windows: content.windows.map {
                .init(windowID: $0.windowID, processID: $0.owningApplication?.processID ?? -1)
            },
            extraWindowIDs: extraExcludedWindowIDs)

        func windows(_ ids: [CGWindowID]) -> [SCWindow] {
            ids.compactMap { id in content.windows.first { $0.windowID == id } }
        }
        switch plan {
        case .excludingApp(let selfApp, let exceptingWindows):
            return SCContentFilter(
                display: display, excludingApplications: [selfApp],
                exceptingWindows: windows(exceptingWindows))
        case .excludingWindows(let ids):
            return SCContentFilter(display: display, excludingWindows: windows(ids))
        }
    }
}

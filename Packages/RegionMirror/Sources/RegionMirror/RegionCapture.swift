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
/// The class never requests Screen Recording permission; it only checks it.
@MainActor
public final class RegionCapture {
    private let sourceDisplayID: CGDirectDisplayID
    private let settings: CaptureSettings
    private var stream: SCStream?
    private var output: StreamOutput?
    private var extraExcludedWindowIDs: [CGWindowID] = []

    /// Called once when the stream stops by itself (not via ``stop()``).
    public var onStop: ((RegionMirrorError) -> Void)?

    /// Complete frames enqueued into the renderer since the last ``start(region:renderer:)``.
    public var deliveredFrameCount: Int { output?.deliveredFrameCount ?? 0 }

    public init(sourceDisplayID: CGDirectDisplayID, settings: CaptureSettings = .init()) {
        self.sourceDisplayID = sourceDisplayID
        self.settings = settings
    }

    /// Starts capturing `region` and rendering into `renderer`.
    /// - Throws: only ``RegionMirrorError``.
    public func start(region: CGRect, renderer: AVSampleBufferVideoRenderer) async throws {
        guard CGPreflightScreenCaptureAccess() else { throw RegionMirrorError.permissionDenied }
        if stream != nil { await stop() }

        let sourceRect = try sourceRect(for: region)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            let display = try display(in: content)
            let filter = makeFilter(display: display, content: content)
            let configuration = settings.makeConfiguration(sourceRect: sourceRect)

            let output = StreamOutput(renderer: renderer) { [weak self] error in
                Task { @MainActor in self?.streamStopped(with: error) }
            }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
            try stream.addStreamOutput(
                output, type: .screen, sampleHandlerQueue: output.sampleHandlerQueue)
            try await stream.startCapture()
            self.stream = stream
            self.output = output
        } catch {
            throw RegionMirrorError(captureError: error)
        }
    }

    /// Moves the captured region on the same display, keeping the stream running.
    /// - Throws: ``RegionMirrorError/notRunning``, ``RegionMirrorError/regionOutsideDisplay``
    ///   or a mapped capture error.
    public func updateRegion(_ region: CGRect) async throws {
        guard let stream else { throw RegionMirrorError.notRunning }
        let sourceRect = try sourceRect(for: region)
        do {
            // updateConfiguration replaces the whole configuration, so always
            // send a complete one.
            try await stream.updateConfiguration(settings.makeConfiguration(sourceRect: sourceRect))
        } catch {
            throw RegionMirrorError(captureError: error)
        }
    }

    /// Additionally excludes windows (by `CGWindowID`) from capture. All windows
    /// of this app are always excluded. Stored before ``start(region:renderer:)``
    /// and applied live afterwards.
    public func excludeWindows(_ ids: [CGWindowID]) async throws {
        extraExcludedWindowIDs = ids
        guard let stream else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
            let display = try display(in: content)
            try await stream.updateContentFilter(makeFilter(display: display, content: content))
        } catch {
            throw RegionMirrorError(captureError: error)
        }
    }

    /// Stops capturing. Safe to call when not running.
    public func stop() async {
        guard let stream, let output else { return }
        self.stream = nil
        self.output = nil
        output.detach()
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(output, type: .screen)
    }

    // MARK: Private

    private func streamStopped(with error: RegionMirrorError) {
        guard stream != nil else { return }
        stream = nil
        output = nil
        onStop?(error)
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
        let selfApp = content.applications.first { $0.processID == pid }
        let plan = ContentFilterPlan.make(
            ownProcessID: pid,
            selfAppFound: selfApp != nil,
            windows: content.windows.map {
                .init(windowID: $0.windowID, processID: $0.owningApplication?.processID ?? -1)
            },
            extraWindowIDs: extraExcludedWindowIDs)

        func windows(_ ids: [CGWindowID]) -> [SCWindow] {
            ids.compactMap { id in content.windows.first { $0.windowID == id } }
        }
        switch (plan, selfApp) {
        case (.excludingApp(let exceptingWindows), let selfApp?):
            return SCContentFilter(
                display: display, excludingApplications: [selfApp],
                exceptingWindows: windows(exceptingWindows))
        case (.excludingWindows(let ids), _):
            return SCContentFilter(display: display, excludingWindows: windows(ids))
        case (.excludingApp, nil):
            // Unreachable: the plan only excludes the app when it was found.
            return SCContentFilter(display: display, excludingWindows: [])
        }
    }
}

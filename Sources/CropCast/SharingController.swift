import AVFoundation
import AppKit
import CoreGraphics
import CropCastCore
import RegionFrame
import RegionMirror
import VirtualDisplay
import os

/// What the session needs from `RegionCapture`. A protocol so the DEBUG
/// self-test can substitute a recording stub for the real ScreenCaptureKit.
@MainActor
protocol RegionCapturing: AnyObject {
    func start(region: CGRect, renderer: AVSampleBufferVideoRenderer) async throws
    func updateRegion(_ region: CGRect) async throws
    func stop() async
}

extension RegionCapture: RegionCapturing {}

/// Everything the session takes from outside, so the self-test can swap it.
struct SharingDependencies {
    var defaults: UserDefaults
    var alerts: any AlertPresenting
    /// `CGPreflightScreenCaptureAccess()` in the real app.
    var preflightScreenCapture: () -> Bool
    var makeCapture: (CGDirectDisplayID) -> any RegionCapturing
    /// Runs before each start step; the self-test throws from it to inject a failure.
    var beforeStep: (StartStepID) async throws -> Void

    @MainActor
    static func live() -> SharingDependencies {
        SharingDependencies(
            defaults: .standard,
            alerts: AlertPresenter(),
            preflightScreenCapture: { CGPreflightScreenCaptureAccess() },
            makeCapture: { RegionCapture(sourceDisplayID: $0) },
            beforeStep: { _ in })
    }
}

/// Start failures that are the app's own, not a module's.
enum SessionError: Error, LocalizedError {
    case screenRecordingPermissionMissing
    case screenDidNotSettle
    case noSourceDisplay
    case frameNotShown(CGDirectDisplayID)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionMissing:
            return "Screen Recording permission is not granted."
        case .screenDidNotSettle:
            return "The virtual display did not appear as a screen in time."
        case .noSourceDisplay:
            return "There is no display to capture from."
        case .frameNotShown(let id):
            return "The frame could not be shown on display \(id)."
        }
    }
}

/// Owns the sharing session: the app state, the frame overlay and, while
/// sharing, the virtual display, the mirror window and the capture.
///
/// The ordering and rollback rules live in `CropCastCore` (`StartSequence`,
/// `SessionMachine`); this class supplies the AppKit/ScreenCaptureKit steps.
@MainActor
final class SharingController {
    static let lastSourceDisplayKey = "CropCast.lastSourceDisplayKey"
    private static let logger = Logger(
        subsystem: "com.github.sv-tmueller.cropcast", category: "session")

    private(set) var state = AppState()
    let overlay: FrameOverlay
    /// The source display of the running session; nil unless a session is up.
    private(set) var sessionSource: CGDirectDisplayID?
    /// The CropCast virtual display of the running session.
    private(set) var virtualDisplayID: CGDirectDisplayID?
    /// Awaited after a quit's teardown, before the terminate reply. The
    /// self-test uses it to check the display count and exit.
    var onQuitTeardownFinished: (@MainActor () async -> Void)?

    private let deps: SharingDependencies
    private var sequence: StartSequence?
    private var mirror: MirrorWindow?
    private var capture: (any RegionCapturing)?
    private var coalescer = LatestWinsCoalescer<CGRect>()
    /// Bumped per session so a late `updateRegion` result of an old one is ignored.
    private var epoch = 0
    private var pendingFailure: (step: StartStepID, error: any Error)?
    private var awaitingTerminateReply = false

    init(deps: SharingDependencies) {
        self.deps = deps
        overlay = FrameOverlay(defaults: deps.defaults)
        overlay.regionDidChange = { [weak self] region in
            MainActor.assumeIsolated { self?.frameRegionDidChange(region) }
        }
    }

    // MARK: Menu and hotkey

    /// Single entry point for menu clicks and the hotkey. `.quit` goes through
    /// `NSApp.terminate` instead (see `StatusMenuController`).
    func apply(_ action: MenuAction) {
        switch action {
        case .toggleSharing:
            perform(state.apply(.toggleSharing))
        case .toggleFrame:
            state.apply(.toggleFrame)
            if overlay.isVisible {
                overlay.hide()
            } else if let display = sessionSource ?? chooseSourceDisplay() {
                overlay.show(on: display)
                rememberPlacement()
            }
            state.isFrameVisible = overlay.isVisible
        case .selectPreset(let preset):
            state.apply(.selectPreset(preset))
            if let display = overlay.region?.displayID ?? chooseSourceDisplay() {
                overlay.apply(preset: regionPreset(for: preset), on: display)
                rememberPlacement()
            }
            state.isFrameVisible = overlay.isVisible
        case .quit:
            break
        }
    }

    private func regionPreset(for preset: FramePreset) -> RegionPreset {
        switch preset {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    // MARK: Quit

    /// Called from `applicationShouldTerminate`. True: quit now. False: a
    /// teardown is in progress and the terminate reply follows (at most 5 s).
    func requestQuit() -> Bool {
        let effects = state.handle(.quitRequested)
        if effects == [.terminate] { return true }
        if !awaitingTerminateReply {
            awaitingTerminateReply = true
            Task { [self] in
                try? await Task.sleep(for: .seconds(5))
                replyToTerminate(runHook: false)
            }
        }
        perform(effects)
        return false
    }

    private func replyToTerminate(runHook: Bool) {
        guard awaitingTerminateReply else { return }
        awaitingTerminateReply = false
        Task { [self] in
            if runHook { await onQuitTeardownFinished?() }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
    }

    // MARK: Session effects

    private func perform(_ effects: [SessionEffect]) {
        for effect in effects {
            switch effect {
            case .startSession: beginStart()
            case .stopSession: beginStop()
            case .showStartFailure: showStartFailure()
            case .terminate: replyToTerminate(runHook: true)
            }
        }
    }

    private func beginStart() {
        epoch += 1
        let sequence = StartSequence(steps: makeSteps())
        self.sequence = sequence
        Task { [self] in
            let outcome = await sequence.run()
            let event: SessionEvent
            switch outcome {
            case .started:
                event = .startSucceeded
            case .failed(let step, let error):
                Self.logger.error("start failed at \(String(describing: step)): \(String(describing: error))")
                pendingFailure = (step, error)
                self.sequence = nil
                event = .startFailed
            case .cancelled(let step):
                Self.logger.info("start cancelled at \(String(describing: step))")
                self.sequence = nil
                event = .startCancelled
            }
            state.isFrameVisible = overlay.isVisible
            perform(state.handle(event))
        }
    }

    private func beginStop() {
        guard let sequence else {
            perform(state.handle(.stopCompleted))
            return
        }
        Task { [self] in
            await sequence.teardown()
            self.sequence = nil
            state.isFrameVisible = overlay.isVisible
            perform(state.handle(.stopCompleted))
        }
    }

    private func showStartFailure() {
        guard let failure = pendingFailure else { return }
        pendingFailure = nil
        if failure.step == .permission {
            deps.alerts.presentPermissionNeeded()
        } else {
            deps.alerts.presentStartFailure(step: failure.step, error: failure.error)
        }
    }

    // MARK: Start steps

    /// Permission gate, display, screen settle, mirror, frame, capture. Each
    /// step returns its undo; `StartSequence` unwinds them in reverse.
    private func makeSteps() -> [StartStep] {
        [
            StartStep(id: .permission) { [self] in
                try await deps.beforeStep(.permission)
                guard deps.preflightScreenCapture() else {
                    throw SessionError.screenRecordingPermissionMissing
                }
                return nil
            },
            StartStep(id: .display) { [self] in
                try await deps.beforeStep(.display)
                // The only strong reference: the display goes away when the undo does.
                let display = try await VirtualDisplay.start()
                virtualDisplayID = display.displayID
                return { [self] _ in
                    display.stop()
                    virtualDisplayID = nil
                }
            },
            StartStep(id: .screen) { [self] in
                try await deps.beforeStep(.screen)
                guard let id = virtualDisplayID else { throw SessionError.screenDidNotSettle }
                try await waitForScreen(id)
                return nil
            },
            StartStep(id: .mirror) { [self] in
                try await deps.beforeStep(.mirror)
                guard let id = virtualDisplayID else { throw SessionError.screenDidNotSettle }
                let window = try MirrorWindow(targetDisplayID: id)
                window.show()
                mirror = window
                return { [self] _ in
                    window.close()
                    mirror = nil
                }
            },
            StartStep(id: .frame) { [self] in
                try await deps.beforeStep(.frame)
                return try showFrameForSession()
            },
            StartStep(id: .capture) { [self] in
                try await deps.beforeStep(.capture)
                return try await startCapture()
            },
        ]
    }

    private func waitForScreen(_ id: CGDirectDisplayID) async throws {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let settled = await pollUntil(timeout: .seconds(2), interval: .milliseconds(50)) {
            ScreenCoordinates.isSettled(
                screenFrame: NSScreen.screens.first { $0.displayID == id }?.frame,
                displayBounds: CGDisplayBounds(id),
                primaryHeight: primaryHeight)
        }
        guard settled else { throw SessionError.screenDidNotSettle }
    }

    private func showFrameForSession() throws -> StartUndo {
        guard let source = chooseSourceDisplay() else { throw SessionError.noSourceDisplay }
        let wasVisible = overlay.isVisible
        overlay.show(on: source)
        rememberPlacement()
        // An unconnected id is a silent no-op in RegionFrame, so check the result.
        guard overlay.isVisible, overlay.region?.displayID == source else {
            if !wasVisible { overlay.hide() }
            state.isFrameVisible = overlay.isVisible
            throw SessionError.frameNotShown(source)
        }
        state.isFrameVisible = true
        sessionSource = source
        return { [self] reason in
            // A rollback restores what the user had; a stop always hides the frame.
            if reason == .stop || !wasVisible { overlay.hide() }
            state.isFrameVisible = overlay.isVisible
            sessionSource = nil
        }
    }

    private func startCapture() async throws -> StartUndo {
        guard let source = sessionSource, let mirror, let region = overlay.region else {
            throw SessionError.frameNotShown(sessionSource ?? 0)
        }
        let capture = deps.makeCapture(source)
        self.capture = capture
        // The start is the first update in flight: frame changes during it are
        // queued and sent once it returns. Changes before this point are ignored
        // because `region` was read just now.
        coalescer.begin()
        do {
            try await capture.start(region: region.rect, renderer: mirror.view.videoRenderer)
        } catch {
            coalescer.reset()
            self.capture = nil
            // A start cancelled from outside throws `.notRunning`: not an error to show.
            if (error as? RegionMirrorError) == .notRunning { throw StartCancelled() }
            throw error
        }
        if let next = coalescer.complete() { sendUpdate(next) }
        return { [self] _ in
            coalescer.reset()
            self.capture = nil
            await capture.stop()
        }
    }

    // MARK: Live region updates

    private func frameRegionDidChange(_ region: FrameRegion) {
        rememberPlacement()
        if let rect = coalescer.submit(region.rect) { sendUpdate(rect) }
    }

    /// Sends one `updateRegion`; when it returns, sends the newest queued rect.
    private func sendUpdate(_ rect: CGRect) {
        guard let capture else { return }
        let epoch = self.epoch
        Task { [self] in
            do {
                try await capture.updateRegion(rect)
            } catch {
                if epoch == self.epoch, self.capture != nil {
                    Self.logger.error("updateRegion failed: \(String(describing: error))")
                }
            }
            guard epoch == self.epoch else { return }
            if let next = coalescer.complete() { sendUpdate(next) }
        }
    }

    // MARK: Source display

    private func chooseSourceDisplay() -> CGDirectDisplayID? {
        let candidates = NSScreen.screens.compactMap { screen -> DisplayCandidate? in
            guard let id = screen.displayID else { return nil }
            return DisplayCandidate(id: id, key: displayKey(id), width: screen.frame.width)
        }
        return SourceDisplayChoice.pick(
            from: candidates, excluding: virtualDisplayID,
            lastUsedKey: deps.defaults.string(forKey: Self.lastSourceDisplayKey))
    }

    /// The last used display is the one of the frame's most recent placement.
    private func rememberPlacement() {
        guard let region = overlay.region else { return }
        deps.defaults.set(displayKey(region.displayID), forKey: Self.lastSourceDisplayKey)
    }
}

// MARK: - Helpers

extension NSScreen {
    /// The display id behind this screen (`NSScreen.cgDirectDisplayID` is macOS 26+).
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// A key that identifies the display across launches: its UUID.
func displayKey(_ id: CGDirectDisplayID) -> String {
    if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
        return CFUUIDCreateString(nil, uuid) as String
    }
    return "cg-\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
}

/// Polls `condition` every `interval` until it holds or `timeout` passes.
@MainActor
func pollUntil(
    timeout: Duration, interval: Duration, _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: interval)
    }
    return true
}

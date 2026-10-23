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
    #if DEBUG
    /// Self-test only: the display the frame step uses instead of the chosen
    /// one, e.g. an unconnected id to reach the `frameNotShown` guard.
    var sourceDisplayOverride: CGDirectDisplayID?
    #endif

    @MainActor
    static func live() -> SharingDependencies {
        SharingDependencies(
            defaults: .standard,
            alerts: AlertPresenter(),
            preflightScreenCapture: { CGPreflightScreenCaptureAccess() },
            makeCapture: { id in
                let capture = RegionCapture(sourceDisplayID: id)
                // Logging only; reacting to a stream that stopped by itself is batch 3.
                capture.onStop = { error in
                    SharingController.logger.error(
                        "capture stopped by itself: \(String(describing: error))")
                }
                return capture
            },
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
    /// Written only when the user chooses from the Display menu. The older
    /// `CropCast.lastSourceDisplayKey` (written by every placement) is ignored.
    static let chosenSourceDisplayKey = "CropCast.chosenSourceDisplayKey"
    fileprivate static let logger = Logger(
        subsystem: "com.github.sv-tmueller.cropcast", category: "session")

    /// Every phase change goes through this property, so one observer covers
    /// Start, a failed or cancelled start, Stop and the quit teardown.
    private(set) var state: AppState {
        didSet {
            if state.phase.isLive != oldValue.phase.isLive { liveDidChange() }
            if state.isFrameLocked != oldValue.isFrameLocked { lockDidChange() }
        }
    }
    /// Called after the live state flipped (the frame style is already updated).
    var onLiveChange: (@MainActor () -> Void)?
    /// Called after the lock flipped (the frame and the saved setting are already
    /// updated), with the new value. Not called for the value loaded at launch.
    var onLockChange: (@MainActor (Bool) -> Void)?
    let overlay: FrameOverlay
    /// The source display of the running session; nil unless a session is up.
    private(set) var sessionSource: CGDirectDisplayID?
    /// The CropCast virtual display of the running session.
    private(set) var virtualDisplayID: CGDirectDisplayID?
    /// Every virtual display id this process has created. `NSScreen.screens`
    /// can list a removed one briefly after Stop, so none is ever a source.
    private(set) var virtualDisplayIDs: Set<CGDirectDisplayID> = []
    /// Awaited after a quit's teardown, before the terminate reply. The
    /// self-test uses it to check the display count and exit.
    #if DEBUG
    var onQuitTeardownFinished: (@MainActor () async -> Void)?
    #endif

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
        let locked = LockFrameSetting.load(from: deps.defaults)
        state = AppState(
            chosenDisplayKey: deps.defaults.string(forKey: Self.chosenSourceDisplayKey),
            isFrameLocked: locked)
        overlay = FrameOverlay(defaults: deps.defaults)
        // The loaded value is applied but not written back.
        overlay.isLocked = locked
        overlay.regionDidChange = { [weak self] region in
            MainActor.assumeIsolated { self?.frameRegionDidChange(region) }
        }
    }

    /// The frame is red exactly while the session is live. On a failed start this
    /// runs before the alert, so the frame is already blue when it appears.
    private func liveDidChange() {
        overlay.style = state.phase.isLive ? .live : .idle
        onLiveChange?()
    }

    /// The lock is single-sourced in `state`: the overlay, the saved setting and
    /// the observers all follow its changes, whichever UI flipped it.
    private func lockDidChange() {
        overlay.isLocked = state.isFrameLocked
        LockFrameSetting.save(state.isFrameLocked, to: deps.defaults)
        onLockChange?(state.isFrameLocked)
    }

    /// The Settings toggle. Does nothing when the lock already has that value.
    func setFrameLocked(_ locked: Bool) {
        guard locked != state.isFrameLocked else { return }
        state.apply(.toggleFrameLock)
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
                // Always pass the display: RegionFrame's own last display is not used.
                overlay.show(on: display)
            }
            state.isFrameVisible = overlay.isVisible
        case .toggleFrameLock:
            state.apply(.toggleFrameLock)
        case .selectPreset(let preset):
            state.apply(.selectPreset(preset))
            if let display = sessionSource ?? chooseSourceDisplay() {
                overlay.apply(preset: regionPreset(for: preset), on: display)
            }
            state.isFrameVisible = overlay.isVisible
        case .selectDisplay(let key):
            guard state.canChooseDisplay,
                let display = sourceCandidates().first(where: { $0.key == key })
            else { break }
            state.apply(.selectDisplay(key: key))
            deps.defaults.set(key, forKey: Self.chosenSourceDisplayKey)
            // Choosing always shows the frame, on the chosen display.
            overlay.show(on: display.id)
            state.isFrameVisible = overlay.isVisible
        case .quit, .openSettings:
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
        #if DEBUG
        let hook = runHook ? onQuitTeardownFinished : nil
        #endif
        Task {
            #if DEBUG
            await hook?()
            #endif
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
                virtualDisplayIDs.insert(display.displayID)
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
        #if DEBUG
        let chosen = deps.sourceDisplayOverride ?? chooseSourceDisplay()
        #else
        let chosen = chooseSourceDisplay()
        #endif
        guard let source = chosen else { throw SessionError.noSourceDisplay }
        let wasVisible = overlay.isVisible
        overlay.show(on: source)
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

    /// The connected displays in `NSScreen.screens` order, with their names.
    private func connectedDisplays() -> [DisplayCandidate] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            return DisplayCandidate(
                id: id, key: displayKey(id), name: screen.localizedName, width: screen.frame.width)
        }
    }

    /// The displays the user can choose from: connected, never a virtual one.
    private func sourceCandidates() -> [DisplayCandidate] {
        connectedDisplays().filter { !virtualDisplayIDs.contains($0.id) }
    }

    /// The display the chosen key names if it is connected, else the widest.
    private func chooseSourceDisplay() -> CGDirectDisplayID? {
        SourceDisplayChoice.pick(
            from: connectedDisplays(), excluding: virtualDisplayIDs,
            chosenKey: state.chosenDisplayKey)
    }

    /// The menu for the current state, with the connected displays.
    func menuEntries() -> [MenuEntry] {
        state.menuEntries(displays: connectedDisplays(), excluding: virtualDisplayIDs)
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

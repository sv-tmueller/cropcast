#if DEBUG
import AVFoundation
import AppKit
import CoreGraphics
import CropCastCore
import Foundation
import RegionMirror

/// `CropCast --self-test` (debug builds only): drives the real Start, Stop and
/// Quit code in this process, with the permission gate bypassed and capture
/// stubbed, and checks the active display count goes N -> N+1 -> N.
///
/// What is real: the virtual display, the screen settle, the mirror window and
/// the frame overlay, plus `StatusMenuController.apply`, `SharingController`
/// and `applicationShouldTerminate`. What is not: capture (a recording stub),
/// the alerts (a logging presenter, so `CGRequestScreenCaptureAccess` is never
/// called), saved state (a throwaway defaults suite) and the hotkey (not
/// registered). The `deny` scenario uses the real `CGPreflightScreenCaptureAccess`.
///
/// Exit status: 0 all scenarios passed (skips allowed), 1 a check failed or the
/// 60 s watchdog fired, 2 a bundled CropCast is already running.
@MainActor
final class SelfTest {
    static let flag = "--self-test"
    private static let bundleID = "com.github.sv-tmueller.cropcast"

    private unowned let delegate: AppDelegate
    private var failures = 0
    private var checks = 0
    private var skips = 0

    init(delegate: AppDelegate) {
        self.delegate = delegate
    }

    func start() {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID)
            .filter { $0.processIdentifier != getpid() }
        if !others.isEmpty {
            say("ABORT: a bundled CropCast is running (pid \(others.map(\.processIdentifier))); quit it first")
            exit(2)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            print("SELF-TEST FAIL: watchdog after 60 s")
            fflush(stdout)
            exit(1)
        }
        Task { [self] in
            await scenarioStop()
            for step in [StartStepID.display, .screen, .mirror, .frame] {
                await scenarioFailure(step, captureError: nil)
            }
            await scenarioFailure(.capture, captureError: InjectedCaptureFailure())
            await scenarioFailure(.capture, captureError: RegionMirrorError.notRunning, cancel: true)
            await scenarioDeny()
            await scenarioQuit()
        }
    }

    // MARK: Scenarios

    /// N -> N+1 -> N through the real menu action path, plus live region updates.
    private func scenarioStop() async {
        let name = "stop"
        let n = displayCount()
        let rig = makeRig(preflight: true)
        say("[\(name)] active displays before: \(n)")

        rig.menu.apply(.toggleSharing)
        expect(rig.sharing.state.phase == .starting, "\(name): phase is starting right after Start")
        expect(await waitPhase(rig, .sharing), "\(name): reached sharing")
        expect(await waitCount(n + 1), "\(name): display count \(n) -> \(n + 1) (now \(displayCount()))")
        expect(rig.alerts.log.isEmpty, "\(name): no alert (\(rig.alerts.log))")

        if let virtual = rig.sharing.virtualDisplayID, let source = rig.sharing.sessionSource {
            let virtualScreen = NSScreen.screens.first { $0.displayID == virtual }
            let sourceScreen = NSScreen.screens.first { $0.displayID == source }
            expect(virtualScreen != nil, "\(name): the virtual display has an NSScreen")
            expect(sourceScreen != nil && source != virtual, "\(name): the source display is a connected, non-virtual screen")

            let mirrors = visibleWindows().filter { $0.level == .screenSaver }
            expect(
                mirrors.count == 1 && mirrors.first?.frame == virtualScreen?.frame,
                "\(name): one mirror window, frame == virtual display's NSScreen.frame")

            let overlay = rig.sharing.overlay
            let panels = Set(overlay.windowNumbers)
            let shown = visibleWindows().filter { panels.contains($0.windowNumber) }
            expect(
                overlay.isVisible && overlay.region?.displayID == source && shown.count == 4
                    && shown.allSatisfy { sourceScreen?.frame.insetBy(dx: -1, dy: -1).contains($0.frame) == true },
                "\(name): the frame is visible on the source display")
            expect(visibleWindows().count == 5, "\(name): exactly mirror + 4 frame panels are visible")
            expect(
                rig.stub.startRegions.last == overlay.region?.rect && rig.stub.startRegions.count == 1,
                "\(name): capture started once with the frame's region")

            await checkPresetUpdatesCapture(rig, name)
        } else {
            expect(false, "\(name): no virtual display or source display in the session")
        }

        rig.menu.apply(.toggleSharing)
        expect(await waitPhase(rig, .idle), "\(name): back to idle after Stop")
        expect(await waitCount(n), "\(name): display count back to \(n) (now \(displayCount()))")
        expect(visibleWindows().isEmpty, "\(name): no visible windows after Stop (\(visibleWindows().count))")
        expect(rig.stub.stopCount == 1, "\(name): capture stopped once")
        expect(!rig.sharing.overlay.isVisible, "\(name): frame hidden after Stop")
        finish(name, rig)
    }

    private func checkPresetUpdatesCapture(_ rig: Rig, _ name: String) async {
        let overlay = rig.sharing.overlay
        let before = overlay.region?.rect
        for preset in [FramePreset.left, .right, .center] {
            rig.menu.apply(.selectPreset(preset))
            if overlay.region?.rect != before { break }
        }
        guard let rect = overlay.region?.rect, rect != before else {
            skip("\(name): no preset moved the frame on this display, live update not exercised")
            return
        }
        let delivered = await pollUntil(timeout: .seconds(3), interval: .milliseconds(20)) {
            rig.stub.updates.last == rect
        }
        expect(delivered, "\(name): a preset reached capture as updateRegion(overlay.region.rect)")
        expect(overlay.isVisible, "\(name): a preset leaves the frame visible")
    }

    /// A failure at `step` leaves N displays, no windows, one alert (none for a cancellation).
    private func scenarioFailure(
        _ step: StartStepID, captureError: (any Error)?, cancel: Bool = false
    ) async {
        let name = cancel ? "fail-at=capture-cancel" : "fail-at=\(step)"
        let n = displayCount()
        let rig = makeRig(preflight: true, failAt: step, captureError: captureError)

        rig.menu.apply(.toggleSharing)
        expect(await waitPhase(rig, .idle), "\(name): back to idle")
        expect(await waitCount(n), "\(name): display count \(n) -> \(n) (now \(displayCount()))")
        expect(visibleWindows().isEmpty, "\(name): no visible windows (\(visibleWindows().count))")
        expect(!rig.sharing.overlay.isVisible, "\(name): frame hidden")
        if cancel {
            expect(rig.alerts.log.isEmpty, "\(name): zero alerts (\(rig.alerts.log))")
        } else {
            expect(rig.alerts.log == [.failure(step)], "\(name): exactly one alert, for this step (\(rig.alerts.log))")
        }
        finish(name, rig)
    }

    /// Uses the real permission check. Skipped when this process has the grant.
    private func scenarioDeny() async {
        let name = "deny"
        guard !CGPreflightScreenCaptureAccess() else {
            skip("\(name): Screen Recording is granted to this process, nothing to deny")
            return
        }
        let n = displayCount()
        let rig = makeRig(preflight: nil)
        rig.menu.apply(.toggleSharing)
        expect(await waitPhase(rig, .idle), "\(name): back to idle")
        expect(await waitCount(n), "\(name): display count \(n) -> \(n) (now \(displayCount()))")
        expect(visibleWindows().isEmpty, "\(name): no visible windows")
        expect(rig.alerts.log == [.permission], "\(name): the permission alert was logged once (\(rig.alerts.log))")
        expect(rig.stub.startRegions.isEmpty, "\(name): capture never started")
        finish(name, rig)
    }

    /// Last: Start, then the real `NSApp.terminate` -> `applicationShouldTerminate`.
    /// The terminate reply is held back (`onQuitTeardownFinished`) so the count
    /// can be polled before the process exits with the overall result.
    private func scenarioQuit() async {
        let name = "quit"
        let n = displayCount()
        let rig = makeRig(preflight: true)
        rig.menu.apply(.toggleSharing)
        let sharing = await waitPhase(rig, .sharing)
        expect(sharing, "\(name): reached sharing")
        expect(await waitCount(n + 1), "\(name): display count \(n) -> \(n + 1) (now \(displayCount()))")
        guard sharing else {
            say("SELF-TEST FAIL: \(failures) of \(checks) checks failed")
            exit(1)
        }

        rig.sharing.onQuitTeardownFinished = { [self] in
            expect(await waitCount(n), "\(name): display count \(n + 1) -> \(n) after Quit (now \(displayCount()))")
            expect(rig.sharing.state.phase == .idle, "\(name): idle after teardown")
            expect(visibleWindows().isEmpty, "\(name): no visible windows")
            expect(rig.stub.stopCount == 1, "\(name): capture stopped once")
            finish(name, rig)
            say(failures == 0
                ? "SELF-TEST PASS: \(checks) checks, \(skips) skipped"
                : "SELF-TEST FAIL: \(failures) of \(checks) checks failed")
            exit(failures == 0 ? 0 : 1)
        }
        // `NSApp.terminate` runs a nested run loop until the terminate reply.
        // Called from inside this Task it would hold the main actor and the
        // teardown could never run, so fire it from a run-loop timer instead,
        // which is what a real menu click is too.
        Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { _ in
            MainActor.assumeIsolated { rig.menu.apply(.quit) }
        }
    }

    // MARK: Rig

    private struct InjectedCaptureFailure: Error, CustomStringConvertible {
        var description: String { "injected failure at capture" }
    }

    private final class LoggingPresenter: AlertPresenting {
        enum Entry: Equatable, CustomStringConvertible {
            case permission, failure(StartStepID)
            var description: String {
                switch self {
                case .permission: return "permission alert"
                case .failure(let step): return "failure alert (\(step))"
                }
            }
        }
        var log: [Entry] = []

        func presentPermissionNeeded() {
            log.append(.permission)
            print("    alert (logged, not shown): Screen Recording permission needed")
        }

        func presentStartFailure(step: StartStepID, error: any Error) {
            log.append(.failure(step))
            print("    alert (logged, not shown): \(StartFailureMessage.make(step: step, error: error).replacingOccurrences(of: "\n\n", with: " | "))")
        }
    }

    private final class StubCapture: RegionCapturing {
        var startRegions: [CGRect] = []
        var updates: [CGRect] = []
        var stopCount = 0
        var startError: (any Error)?

        func start(region: CGRect, renderer: AVSampleBufferVideoRenderer) async throws {
            startRegions.append(region)
            if let startError { throw startError }
        }

        func updateRegion(_ region: CGRect) async throws { updates.append(region) }
        func stop() async { stopCount += 1 }
    }

    private struct Rig {
        let sharing: SharingController
        let menu: StatusMenuController
        let alerts: LoggingPresenter
        let stub: StubCapture
        let suite: String
    }

    /// `preflight` nil means the real `CGPreflightScreenCaptureAccess()`.
    private func makeRig(
        preflight: Bool?, failAt: StartStepID? = nil, captureError: (any Error)? = nil
    ) -> Rig {
        let suite = "com.github.sv-tmueller.cropcast.selftest.\(UUID().uuidString)"
        let alerts = LoggingPresenter()
        let stub = StubCapture()
        stub.startError = captureError
        struct Injected: Error, CustomStringConvertible {
            let step: StartStepID
            var description: String { "injected failure at \(step)" }
        }
        let deps = SharingDependencies(
            defaults: UserDefaults(suiteName: suite) ?? .standard,
            alerts: alerts,
            preflightScreenCapture: { preflight ?? CGPreflightScreenCaptureAccess() },
            makeCapture: { _ in stub },
            beforeStep: { step in
                // The capture step fails inside the stub instead (`captureError`).
                if step == failAt, step != .capture { throw Injected(step: step) }
            })
        let sharing = SharingController(deps: deps)
        let menu = StatusMenuController(sharing: sharing)
        delegate.menuController = menu
        return Rig(sharing: sharing, menu: menu, alerts: alerts, stub: stub, suite: suite)
    }

    private func finish(_ name: String, _ rig: Rig) {
        NSStatusBar.system.removeStatusItem(rig.menu.statusItem)
        UserDefaults.standard.removePersistentDomain(forName: rig.suite)
        say("[\(name)] done")
    }

    // MARK: Helpers

    private func displayCount() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        return Int(count)
    }

    private func waitCount(_ expected: Int) async -> Bool {
        await pollUntil(timeout: .seconds(5), interval: .milliseconds(50)) { displayCount() == expected }
    }

    private func waitPhase(_ rig: Rig, _ phase: SessionPhase) async -> Bool {
        await pollUntil(timeout: .seconds(15), interval: .milliseconds(25)) { rig.sharing.state.phase == phase }
    }

    /// Visible windows of this process, without the status item's window.
    private func visibleWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && !String(describing: type(of: $0)).contains("StatusBar") }
    }

    private func expect(_ ok: Bool, _ what: String) {
        checks += 1
        if !ok { failures += 1 }
        say("  \(ok ? "PASS" : "FAIL") \(what)")
    }

    private func skip(_ what: String) {
        skips += 1
        say("  SKIP \(what)")
    }

    private func say(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
#endif

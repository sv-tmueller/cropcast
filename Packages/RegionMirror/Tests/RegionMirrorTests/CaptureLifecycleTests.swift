import CoreGraphics
import Testing

@testable import RegionMirror

/// `String` stands in for the stream value (`SCStream` + output in production).
@Suite("CaptureLifecycle")
struct CaptureLifecycleTests {
    private typealias Lifecycle = CaptureLifecycle<String>

    private let rectA = CGRect(x: 0, y: 0, width: 160, height: 90)
    private let rectB = CGRect(x: 10, y: 10, width: 320, height: 180)
    private let failure = RegionMirrorError.captureFailed(code: 7, description: "stream died")

    /// A lifecycle that has started and committed `stream`.
    private func running(_ stream: String = "s1") -> Lifecycle {
        var lifecycle = Lifecycle()
        let token = lifecycle.beginStart()!
        let committed1 = lifecycle.commit(token, stream: stream)
        #expect(committed1)
        return lifecycle
    }

    // MARK: Race 1: stop while starting

    @Test("stop while starting goes idle and invalidates the token")
    func stopWhileStarting() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        let stopped1 = lifecycle.stop()
        #expect(stopped1 == nil)
        #expect(lifecycle.phase == .idle)
        #expect(!lifecycle.isCurrent(t1))
        let committed1 = lifecycle.commit(t1, stream: "late")
        #expect(!committed1)
        #expect(lifecycle.phase == .idle)
    }

    @Test("a stale commit leaves a newer start untouched")
    func staleCommitKeepsNewerStart() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        let committed1 = lifecycle.commit(t1, stream: "old")
        #expect(!committed1)
        #expect(lifecycle.phase == .starting(t2))
        let committed2 = lifecycle.commit(t2, stream: "new")
        #expect(committed2)
        #expect(lifecycle.runningStream == "new")
    }

    // MARK: Race 2: concurrent starts

    @Test("beginStart while starting or running is refused and changes nothing")
    func beginStartRefused() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        let started1 = lifecycle.beginStart()
        #expect(started1 == nil)
        #expect(lifecycle.phase == .starting(t1))
        let committed1 = lifecycle.commit(t1, stream: "s1")
        #expect(committed1)
        let started2 = lifecycle.beginStart()
        #expect(started2 == nil)
        #expect(lifecycle.phase == .running(t1, "s1"))
    }

    @Test("beginStart after stop hands out a new distinct token")
    func beginStartAfterStop() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        #expect(t1 != t2)
    }

    // MARK: Race 3: region updates during start

    @Test("regionUpdate is notRunning when idle, deferred when starting, apply when running")
    func regionUpdatePerPhase() {
        var lifecycle = Lifecycle()
        let decision1 = lifecycle.regionUpdate(rectA)
        #expect(decision1 == .notRunning)
        let t1 = lifecycle.beginStart()!
        let decision2 = lifecycle.regionUpdate(rectA)
        #expect(decision2 == .deferred)
        let committed1 = lifecycle.commit(t1, stream: "s1")
        #expect(committed1)
        let decision3 = lifecycle.regionUpdate(rectA)
        #expect(decision3 == .apply("s1"))
    }

    @Test("two deferred rects: take returns the latest, then nil")
    func latestDeferredWins() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.regionUpdate(rectA)
        _ = lifecycle.regionUpdate(rectB)
        let taken1 = lifecycle.takePendingRegion(t1)
        #expect(taken1 == rectB)
        let taken2 = lifecycle.takePendingRegion(t1)
        #expect(taken2 == nil)
    }

    @Test("stop clears the pending region and a new start does not inherit it")
    func stopClearsPending() {
        var lifecycle = Lifecycle()
        _ = lifecycle.beginStart()!
        _ = lifecycle.regionUpdate(rectA)
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        let taken1 = lifecycle.takePendingRegion(t2)
        #expect(taken1 == nil)
    }

    @Test("startFailed clears the pending region")
    func startFailedClearsPending() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.regionUpdate(rectA)
        lifecycle.startFailed(t1)
        #expect(lifecycle.phase == .idle)
        let t2 = lifecycle.beginStart()!
        let taken1 = lifecycle.takePendingRegion(t2)
        #expect(taken1 == nil)
    }

    @Test("a stale token cannot take the pending region of a newer start")
    func stalePendingTake() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        _ = lifecycle.regionUpdate(rectA)
        let taken1 = lifecycle.takePendingRegion(t1)
        #expect(taken1 == nil)
        let taken2 = lifecycle.takePendingRegion(t2)
        #expect(taken2 == rectA)
    }

    // MARK: Race 4: wrong stream

    @Test("startFailed with a stale token does not cancel a newer start")
    func staleStartFailed() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        lifecycle.startFailed(t1)
        #expect(lifecycle.phase == .starting(t2))
    }

    @Test("streamEnded from an old stream does not drop the newer one")
    func staleStreamEnded() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.commit(t1, stream: "old")
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        _ = lifecycle.commit(t2, stream: "new")

        let reported1 = lifecycle.streamEnded(t1, error: failure)
        #expect(!reported1)
        #expect(lifecycle.phase == .running(t2, "new"))
        let reported2 = lifecycle.streamEnded(t2, error: failure)
        #expect(reported2)
        #expect(lifecycle.phase == .idle)
    }

    @Test("streamEnded while still starting goes idle without reporting, and the commit fails")
    func streamEndedWhileStarting() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        let reported1 = lifecycle.streamEnded(t1, error: failure)
        #expect(!reported1)
        #expect(lifecycle.phase == .idle)
        #expect(!lifecycle.isCurrent(t1))
        let committed1 = lifecycle.commit(t1, stream: "s1")
        #expect(!committed1)
    }

    // MARK: Ended during start is not a cancellation

    @Test("a stream that ended while starting records its error for that start")
    func endedWhileStartingRecordsError() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.streamEnded(t1, error: failure)
        #expect(lifecycle.endedError(for: t1) == failure)
    }

    @Test("stop while starting records no error, so the start reads as cancelled")
    func stopWhileStartingRecordsNothing() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.stop()
        #expect(lifecycle.endedError(for: t1) == nil)
    }

    @Test("stop after the stream ended during start wins: the start reads as cancelled")
    func stopAfterEndedWhileStarting() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.streamEnded(t1, error: failure)
        _ = lifecycle.stop()
        #expect(lifecycle.endedError(for: t1) == nil)
    }

    @Test("a stale-token end during a newer start records nothing for the new token")
    func staleEndRecordsNothing() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.stop()
        let t2 = lifecycle.beginStart()!
        let reported1 = lifecycle.streamEnded(t1, error: failure)
        #expect(!reported1)
        #expect(lifecycle.phase == .starting(t2))
        #expect(lifecycle.endedError(for: t2) == nil)
        #expect(lifecycle.endedError(for: t1) == nil)
    }

    @Test("a running stream ending records no start error")
    func runningEndRecordsNothing() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.commit(t1, stream: "s1")
        let reported1 = lifecycle.streamEnded(t1, error: failure)
        #expect(reported1)
        #expect(lifecycle.endedError(for: t1) == nil)
    }

    @Test("a new beginStart clears the recorded error")
    func beginStartClearsEndedError() {
        var lifecycle = Lifecycle()
        let t1 = lifecycle.beginStart()!
        _ = lifecycle.streamEnded(t1, error: failure)
        let t2 = lifecycle.beginStart()!
        #expect(lifecycle.endedError(for: t1) == nil)
        #expect(lifecycle.endedError(for: t2) == nil)
    }

    @Test("stop while running returns the stream once, the second stop returns nil")
    func stopReturnsStreamOnce() {
        var lifecycle = running("s1")
        let stopped1 = lifecycle.stop()
        #expect(stopped1 == "s1")
        #expect(lifecycle.phase == .idle)
        #expect(lifecycle.runningStream == nil)
        let stopped2 = lifecycle.stop()
        #expect(stopped2 == nil)
    }

    @Test("runningStream is only set while running")
    func runningStreamPerPhase() {
        var lifecycle = Lifecycle()
        #expect(lifecycle.runningStream == nil)
        let t1 = lifecycle.beginStart()!
        #expect(lifecycle.runningStream == nil)
        _ = lifecycle.commit(t1, stream: "s1")
        #expect(lifecycle.runningStream == "s1")
    }
}

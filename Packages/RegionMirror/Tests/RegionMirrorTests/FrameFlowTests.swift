import ScreenCaptureKit
import Testing

@testable import RegionMirror

@Suite("FrameFlow")
struct FrameFlowTests {
    private func counters(
        received: Int = 0, complete: Int = 0, idle: Int = 0, other: Int = 0,
        enqueued: Int = 0, droppedNotReady: Int = 0, flushes: Int = 0
    ) -> FrameCounters {
        FrameCounters(
            received: received, complete: complete, idle: idle, other: other,
            enqueued: enqueued, droppedNotReady: droppedNotReady, flushes: flushes)
    }

    private let window = Duration.seconds(2)

    // MARK: FrameStatusBucket

    @Test(
        "every SCFrameStatus maps to a bucket",
        arguments: [
            (SCFrameStatus.complete, FrameStatusBucket.complete),
            (.idle, .idle),
            (.blank, .other),
            (.suspended, .other),
            (.started, .other),
            (.stopped, .other),
        ] as [(SCFrameStatus, FrameStatusBucket)])
    func bucketForStatus(status: SCFrameStatus, expected: FrameStatusBucket) {
        #expect(FrameStatusBucket(rawStatus: status.rawValue) == expected)
    }

    @Test("an unreadable or unknown status is other")
    func bucketForUnreadableStatus() {
        #expect(FrameStatusBucket(rawStatus: nil) == .other)
        #expect(FrameStatusBucket(rawStatus: 99) == .other)
    }

    // MARK: FrameCounters

    @Test("record counts received, the bucket and the outcome")
    func recordCounts() {
        var c = FrameCounters()
        c.record(.complete, .enqueued)
        c.record(.complete, .droppedNotReady)
        c.record(.idle, .notComplete)
        c.record(.other, .notComplete)
        #expect(
            c == counters(
                received: 4, complete: 2, idle: 1, other: 1, enqueued: 1, droppedNotReady: 1))
    }

    @Test("recordFlush only counts flushes")
    func recordFlush() {
        var c = FrameCounters()
        c.recordFlush()
        #expect(c == counters(flushes: 1))
    }

    @Test("subtraction gives the per-field window delta")
    func subtraction() {
        let before = counters(received: 5, complete: 3, idle: 1, other: 1, enqueued: 3)
        let after = counters(
            received: 9, complete: 5, idle: 2, other: 2, enqueued: 4, droppedNotReady: 1,
            flushes: 1)
        #expect(
            after - before
                == counters(
                    received: 4, complete: 2, idle: 1, other: 1, enqueued: 1,
                    droppedNotReady: 1, flushes: 1))
    }

    @Test("a callback counted once at exit keeps complete >= enqueued + dropped in every window")
    func windowInvariant() {
        var total = FrameCounters()
        total.record(.complete, .enqueued)
        let baseline = total
        // One callback straddles the window boundary: it is counted only when it exits.
        total.record(.complete, .droppedNotReady)
        total.record(.complete, .enqueued)
        let delta = total - baseline
        #expect(delta.complete >= delta.enqueued + delta.droppedNotReady)
    }

    @Test("logText carries all seven keys")
    func logTextKeys() {
        let text = counters(
            received: 1, complete: 2, idle: 3, other: 4, enqueued: 5, droppedNotReady: 6,
            flushes: 7
        ).logText
        #expect(
            text
                == "received=1 complete=2 idle=3 other=4 enqueued=5 droppedNotReady=6 flushes=7")
    }

    // MARK: classify

    @Test("no callbacks at all is silent")
    func silent() {
        let state = FrameFlowState.classify(
            window: counters(), windowLength: window, callbackRunningFor: nil)
        #expect(state == .silent)
    }

    @Test("complete frames that were never enqueued are rendererBlocked")
    func rendererBlocked() {
        let state = FrameFlowState.classify(
            window: counters(received: 3, complete: 3, droppedNotReady: 3), windowLength: window,
            callbackRunningFor: nil)
        #expect(state == .rendererBlocked)
    }

    @Test("a callback running longer than the window is callbackStuck")
    func callbackStuck() {
        let state = FrameFlowState.classify(
            window: counters(received: 3, complete: 3, enqueued: 3), windowLength: window,
            callbackRunningFor: .seconds(3))
        #expect(state == .callbackStuck)
    }

    @Test("frames enqueued is healthy")
    func healthyEnqueued() {
        let state = FrameFlowState.classify(
            window: counters(received: 3, complete: 3, enqueued: 3), windowLength: window,
            callbackRunningFor: nil)
        #expect(state == .healthy)
    }

    @Test("only idle frames is healthy")
    func healthyIdleOnly() {
        let state = FrameFlowState.classify(
            window: counters(received: 4, idle: 4), windowLength: window, callbackRunningFor: nil)
        #expect(state == .healthy)
    }

    @Test("only other statuses is healthy")
    func healthyOtherOnly() {
        let state = FrameFlowState.classify(
            window: counters(received: 4, other: 4), windowLength: window, callbackRunningFor: nil)
        #expect(state == .healthy)
    }

    @Test("some drops with at least one enqueued is healthy")
    func healthyWithDrops() {
        let state = FrameFlowState.classify(
            window: counters(received: 4, complete: 4, enqueued: 1, droppedNotReady: 3),
            windowLength: window, callbackRunningFor: nil)
        #expect(state == .healthy)
    }

    @Test("stuck wins over silent")
    func stuckBeatsSilent() {
        let state = FrameFlowState.classify(
            window: counters(), windowLength: window, callbackRunningFor: .seconds(5))
        #expect(state == .callbackStuck)
    }

    @Test("stuck wins over rendererBlocked")
    func stuckBeatsBlocked() {
        let state = FrameFlowState.classify(
            window: counters(received: 2, complete: 2, droppedNotReady: 2), windowLength: window,
            callbackRunningFor: .seconds(5))
        #expect(state == .callbackStuck)
    }

    @Test("a callback running exactly as long as the window is not stuck")
    func exactlyWindowIsNotStuck() {
        let state = FrameFlowState.classify(
            window: counters(), windowLength: window, callbackRunningFor: window)
        #expect(state == .silent)
    }

    // MARK: Monitor

    private func runningMonitor(silentIsFault: Bool = true) -> FrameFlowMonitor {
        var monitor = FrameFlowMonitor(silentIsFault: silentIsFault)
        let started = monitor.start(baseline: FrameCounters())
        #expect(started)
        return monitor
    }

    private func healthyWindow(_ total: inout FrameCounters) {
        total.record(.complete, .enqueued)
    }

    private func tick(
        _ monitor: inout FrameFlowMonitor, _ total: FrameCounters, runningFor: Duration? = nil
    ) -> FrameFlowTick? {
        monitor.tick(counters: total, windowLength: window, callbackRunningFor: runningFor)
    }

    @Test("a healthy first window logs nothing")
    func healthyStartIsQuiet() throws {
        var monitor = runningMonitor()
        var total = FrameCounters()
        healthyWindow(&total)
        let result = try #require(tick(&monitor, total))
        #expect(result.state == .healthy)
        #expect(result.transition == nil)
        #expect(!result.heartbeat)
    }

    @Test("state changes are logged on change only")
    func logsOnChangeOnly() throws {
        var monitor = runningMonitor()
        var total = FrameCounters()
        var transitions: [FrameFlowTick.Transition] = []
        // healthy, healthy, silent, silent, healthy
        for step in 0..<5 {
            if step < 2 || step == 4 { healthyWindow(&total) }
            if let t = try #require(tick(&monitor, total)).transition { transitions.append(t) }
        }
        #expect(
            transitions == [
                .init(from: .healthy, to: .silent, oldStateLasted: .seconds(4), level: .error),
                .init(from: .silent, to: .healthy, oldStateLasted: .seconds(4), level: .notice),
            ])
    }

    @Test(
        "the level of a change depends on the target state and silentIsFault",
        arguments: [
            (FrameFlowState.silent, true, FrameFlowLogLevel.error),
            (.silent, false, .notice),
            (.rendererBlocked, true, .error),
            (.rendererBlocked, false, .error),
            (.callbackStuck, true, .error),
            (.callbackStuck, false, .error),
        ] as [(FrameFlowState, Bool, FrameFlowLogLevel)])
    func transitionLevel(target: FrameFlowState, silentIsFault: Bool, level: FrameFlowLogLevel)
        throws
    {
        var monitor = runningMonitor(silentIsFault: silentIsFault)
        var total = FrameCounters()
        var runningFor: Duration?
        switch target {
        case .silent: break
        case .rendererBlocked: total.record(.complete, .droppedNotReady)
        case .callbackStuck, .healthy: runningFor = .seconds(9)
        }
        let result = try #require(tick(&monitor, total, runningFor: runningFor))
        #expect(result.state == target)
        #expect(result.transition?.level == level)
    }

    @Test("a change back into healthy is a notice with either silentIsFault")
    func intoHealthyIsNotice() throws {
        for silentIsFault in [true, false] {
            var monitor = runningMonitor(silentIsFault: silentIsFault)
            var total = FrameCounters()
            _ = tick(&monitor, total)  // silent
            healthyWindow(&total)
            let result = try #require(tick(&monitor, total))
            #expect(result.transition?.to == .healthy)
            #expect(result.transition?.level == .notice)
        }
    }

    @Test("a heartbeat comes on tick 30 and tick 60 only")
    func heartbeatCadence() throws {
        var monitor = runningMonitor()
        var total = FrameCounters()
        var heartbeats: [Int] = []
        for n in 1...61 {
            healthyWindow(&total)
            if try #require(tick(&monitor, total)).heartbeat { heartbeats.append(n) }
        }
        #expect(heartbeats == [30, 60])
    }

    @Test("the flush flag is set from the window's flush count")
    func flushFlag() throws {
        var monitor = runningMonitor()
        var total = FrameCounters()
        total.record(.complete, .enqueued)
        total.recordFlush()
        total.recordFlush()
        let first = try #require(tick(&monitor, total))
        #expect(first.logsFlush)
        #expect(first.window.flushes == 2)
        total.record(.complete, .enqueued)
        let second = try #require(tick(&monitor, total))
        #expect(!second.logsFlush)
    }

    @Test("the renderer is read on a transition or heartbeat, never while stuck")
    func readsRenderer() throws {
        var monitor = runningMonitor()
        var total = FrameCounters()
        healthyWindow(&total)
        let quiet = try #require(tick(&monitor, total))
        #expect(!quiet.readsRenderer)

        // A transition reads it.
        let silent = try #require(tick(&monitor, total))
        #expect(silent.transition != nil)
        #expect(silent.readsRenderer)

        // Stuck: transition, but no renderer read.
        let stuck = try #require(tick(&monitor, total, runningFor: .seconds(9)))
        #expect(stuck.state == .callbackStuck)
        #expect(stuck.transition != nil)
        #expect(!stuck.readsRenderer)
    }

    @Test("a heartbeat while stuck does not read the renderer")
    func heartbeatWhileStuckDoesNotRead() throws {
        var monitor = runningMonitor()
        let total = FrameCounters()
        var last: FrameFlowTick?
        for _ in 1...30 { last = tick(&monitor, total, runningFor: .seconds(99)) }
        let result = try #require(last)
        #expect(result.heartbeat)
        #expect(result.state == .callbackStuck)
        #expect(!result.readsRenderer)
    }

    @Test("a heartbeat while healthy reads the renderer")
    func heartbeatReads() throws {
        var monitor = runningMonitor()
        var total = FrameCounters()
        var last: FrameFlowTick?
        for _ in 1...30 {
            healthyWindow(&total)
            last = tick(&monitor, total)
        }
        #expect(try #require(last).readsRenderer)
    }

    // MARK: Monitor phases

    @Test("a tick before start or after stop returns nil")
    func tickOutsideRunning() {
        var monitor = FrameFlowMonitor()
        let beforeStart = tick(&monitor, FrameCounters())
        #expect(beforeStart == nil)
        _ = monitor.start(baseline: FrameCounters())
        _ = monitor.stop(.requested)
        let afterStop = tick(&monitor, FrameCounters())
        #expect(afterStop == nil)
    }

    @Test("start works once and never after a stop")
    func startRules() {
        var monitor = FrameFlowMonitor()
        let first = monitor.start(baseline: FrameCounters())
        let second = monitor.start(baseline: FrameCounters())
        _ = monitor.stop(.requested)
        let afterStop = monitor.start(baseline: FrameCounters())
        #expect(first)
        #expect(!second)
        #expect(!afterStop)
    }

    @Test("stop by request logs only when running")
    func requestedStopRules() {
        var monitor = FrameFlowMonitor()
        let beforeStart = monitor.stop(.requested)
        _ = monitor.start(baseline: FrameCounters())
        let running = monitor.stop(.requested)
        let again = monitor.stop(.requested)
        #expect(!beforeStart)
        #expect(running)
        #expect(!again)
    }

    @Test("a stream end logs unless already stopped")
    func endedStopRules() {
        var early = FrameFlowMonitor()
        let earlyFirst = early.stop(.ended)
        let earlyAgain = early.stop(.ended)
        let earlyStart = early.start(baseline: FrameCounters())
        #expect(earlyFirst)
        #expect(!earlyAgain)
        #expect(!earlyStart)

        var afterRequest = FrameFlowMonitor()
        _ = afterRequest.start(baseline: FrameCounters())
        _ = afterRequest.stop(.requested)
        let ended = afterRequest.stop(.ended)
        #expect(!ended)

        var running = FrameFlowMonitor()
        _ = running.start(baseline: FrameCounters())
        let runningEnded = running.stop(.ended)
        #expect(runningEnded)
    }

    // MARK: Log lines

    @Test("the state change line names both states, the duration, window and renderer")
    func stateChangeLine() {
        let line = FrameFlowLog.stateChange(
            .init(from: .healthy, to: .silent, oldStateLasted: .milliseconds(4_250), level: .error),
            window: counters(), renderer: "status=rendering")
        #expect(
            line
                == "frame flow healthy -> silent after 4.2 s window: "
                + "received=0 complete=0 idle=0 other=0 enqueued=0 droppedNotReady=0 flushes=0 "
                + "renderer: status=rendering")
    }

    @Test("the renderer snapshot text covers each status and a missing error")
    func rendererSnapshotText() {
        let snapshot = RendererSnapshot(
            statusRawValue: 2, error: nil, isReady: false, requiresFlush: true)
        #expect(snapshot.logText == "status=failed error=none ready=false requiresFlush=true")
        #expect(RendererSnapshot.statusName(0) == "unknown")
        #expect(RendererSnapshot.statusName(1) == "rendering")
        #expect(RendererSnapshot.statusName(7) == "raw 7")
    }

    @Test("the stream-ended line carries domain, code and description")
    func streamEndedLine() {
        let line = FrameFlowLog.streamEnded(
            domain: "SCStreamErrorDomain", code: -3815, description: "stopped", total: counters())
        #expect(
            line.hasPrefix(
                "stream ended by itself domain=SCStreamErrorDomain code=-3815 "
                    + "description=stopped total: received=0"))
    }

    @Test("start, stop, heartbeat and flush lines keep their stable keys")
    func otherLines() {
        let info = CaptureStartInfo(
            displayID: 3, sourceRect: .init(x: 10, y: 20, width: 1280, height: 720), width: 2560,
            height: 1440, framesPerSecond: 30)
        #expect(
            FrameFlowLog.started(info)
                == "capture started display=3 sourceRect=10,20,1280,720 output=2560x1440 fps=30")
        #expect(
            FrameFlowLog.stopped(total: counters())
                .hasPrefix("capture stopped by request total: received=0"))
        let heartbeat = FrameFlowLog.heartbeat(state: .healthy, total: counters(), renderer: "r")
        #expect(heartbeat.hasPrefix("heartbeat state=healthy total: received=0"))
        #expect(heartbeat.hasSuffix(" renderer: r"))
        #expect(
            FrameFlowLog.flushed(flushes: 2, error: nil)
                == "renderer flushed after failed flushes=2 error=none")
        #expect(
            FrameFlowLog.flushed(flushes: 1, error: "d 1 x")
                == "renderer flushed after failed flushes=1 error=d 1 x")
        #expect(FrameFlowLog.callbackInFlight == "not read (callback in flight)")
    }
}

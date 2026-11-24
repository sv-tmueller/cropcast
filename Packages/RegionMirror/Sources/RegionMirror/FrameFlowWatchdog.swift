import AVFoundation
import Dispatch
import Foundation
import os

/// What the watchdog reads from `StreamOutput` each tick.
struct FrameFlowSample: Sendable {
    var counters: FrameCounters
    /// When the current frame callback was entered, nil when none is running.
    var callbackEnteredAt: SuspendingClock.Instant?
    /// The renderer error text captured just before the last flush, nil if none.
    var lastFlushError: String?
}

/// Logs the frame flow (see ``FrameFlowMonitor``) from a timer that does not
/// depend on frames arriving.
///
/// Why it is built this way:
/// - The timer runs on its own queue, never `sampleHandlerQueue`, which may be
///   the thing that is blocked.
/// - One lock guards the monitor, the timer and the last tick time. `start` and
///   `stop` run on the calling thread under it and log their own line there, so
///   no line can follow the stop line and no thread (the main actor in
///   particular) ever waits on the watchdog queue.
/// - A tick reads the renderer outside the lock, and never while a frame
///   callback is stuck, because a hung `enqueue` or `flush` may hold the lock
///   the renderer getters need.
/// - It holds the renderer and a sample closure that weakly captures the
///   `StreamOutput`, so it never keeps the output alive. The timer handler
///   captures this object weakly too.
///
/// `@unchecked Sendable`: `AVSampleBufferVideoRenderer` is thread-safe (same
/// reasoning as `StreamOutput`); everything else is behind the lock.
final class FrameFlowWatchdog: @unchecked Sendable {
    enum StopKind {
        case requested
        case ended(domain: String, code: Int, description: String)
    }

    private struct Gate {
        var monitor = FrameFlowMonitor()
        var timer: (any DispatchSourceTimer)?
        var lastTickAt: SuspendingClock.Instant?
        var sample: (@Sendable () -> FrameFlowSample?)?
    }

    private static let tickInterval = 2

    private let renderer: AVSampleBufferVideoRenderer
    private let queue = DispatchQueue(label: "cropcast.regionmirror.watchdog")
    private let clock = SuspendingClock()
    private let logger = Logger(subsystem: "com.github.sv-tmueller.cropcast", category: "capture")
    private let gate = OSAllocatedUnfairLock(uncheckedState: Gate())

    init(renderer: AVSampleBufferVideoRenderer) {
        self.renderer = renderer
    }

    deinit {
        gate.withLockUnchecked { $0.timer?.cancel() }
    }

    /// Logs the start line and starts the timer. Does nothing after a stop or a second start.
    func start(_ info: CaptureStartInfo, sample: @escaping @Sendable () -> FrameFlowSample?) {
        guard let first = sample() else { return }
        let now = clock.now
        gate.withLockUnchecked { gate in
            guard gate.monitor.start(baseline: first.counters) else { return }
            gate.sample = sample
            gate.lastTickAt = now
            // Created here only: releasing a source that was never resumed crashes.
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + .seconds(Self.tickInterval),
                repeating: .seconds(Self.tickInterval), leeway: .milliseconds(100))
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.resume()
            gate.timer = timer
            log(.notice, FrameFlowLog.started(info))
        }
    }

    /// Logs the stop line (at most once, and only if it applies), then stops the
    /// timer. Synchronous: the line is out before this returns, so a caller
    /// that exits the process right after still has it in the log.
    func stop(_ kind: StopKind, total: FrameCounters) {
        gate.withLockUnchecked { gate in
            let reason: FrameFlowMonitor.StopReason
            switch kind {
            case .requested: reason = .requested
            case .ended: reason = .ended
            }
            if gate.monitor.stop(reason) {
                switch kind {
                case .requested:
                    log(.notice, FrameFlowLog.stopped(total: total))
                case .ended(let domain, let code, let description):
                    log(
                        .error,
                        FrameFlowLog.streamEnded(
                            domain: domain, code: code, description: description, total: total))
                }
            }
            gate.timer?.cancel()
            gate.timer = nil
            gate.sample = nil
        }
    }

    // MARK: Tick

    private func tick() {
        // Sample first, clock second: the entry time can never be after `now`.
        guard let sample = gate.withLockUnchecked({ $0.sample }), let reading = sample() else {
            cancelTimer()
            return
        }
        let now = clock.now

        // 1. Decide under the lock.
        let decision: FrameFlowTick? = gate.withLockUnchecked { gate in
            guard let last = gate.lastTickAt else { return nil }
            let length = last.duration(to: now)
            gate.lastTickAt = now
            return gate.monitor.tick(
                counters: reading.counters, windowLength: length,
                callbackRunningFor: reading.callbackEnteredAt.map { $0.duration(to: now) })
        }
        guard let tick = decision else {
            cancelTimer()
            return
        }

        // 2. Read the renderer without any lock, and not while a callback is stuck.
        let rendererText =
            tick.readsRenderer ? snapshot().logText : FrameFlowLog.callbackInFlight

        // 3. Log under the lock, only if still running: no line follows the stop line.
        gate.withLockUnchecked { gate in
            guard gate.monitor.isRunning else { return }
            if tick.logsFlush {
                log(
                    .notice,
                    FrameFlowLog.flushed(
                        flushes: tick.window.flushes, error: reading.lastFlushError))
            }
            if let transition = tick.transition {
                log(
                    transition.level,
                    FrameFlowLog.stateChange(
                        transition, window: tick.window, renderer: rendererText))
            }
            if tick.heartbeat {
                log(
                    .notice,
                    FrameFlowLog.heartbeat(
                        state: tick.state, total: reading.counters, renderer: rendererText))
            }
        }
    }

    private func cancelTimer() {
        gate.withLockUnchecked { gate in
            gate.timer?.cancel()
            gate.timer = nil
            gate.sample = nil
        }
    }

    private func snapshot() -> RendererSnapshot {
        RendererSnapshot(
            statusRawValue: renderer.status.rawValue,
            error: renderer.error.map { Self.describe($0).text },
            isReady: renderer.isReadyForMoreMediaData,
            requiresFlush: renderer.requiresFlushToResumeDecoding)
    }

    /// Domain, code and description of any error (system error text only).
    static func describe(_ error: any Error) -> (domain: String, code: Int, description: String, text: String) {
        let nsError = error as NSError
        let description = nsError.localizedDescription
        return (
            nsError.domain, nsError.code, description,
            "\(nsError.domain) \(nsError.code) \(description)"
        )
    }

    /// Every interpolated value is `.public`; the levels are only notice and error.
    private func log(_ level: FrameFlowLogLevel, _ text: String) {
        switch level {
        case .notice: logger.log(level: .default, "\(text, privacy: .public)")
        case .error: logger.log(level: .error, "\(text, privacy: .public)")
        }
    }
}

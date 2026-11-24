import CoreGraphics
import Foundation
import ScreenCaptureKit

// Pure value logic for the frame-flow log (no clocks, no timers, no
// ScreenCaptureKit runtime), unit-tested like `CaptureLifecycle`. The timer,
// the lock and the logger live in `FrameFlowWatchdog`.

/// Which bucket a callback's `SCFrameStatus` falls into.
enum FrameStatusBucket: Equatable, Sendable {
    case complete
    case idle
    /// Blank, suspended, started, stopped, an unreadable or an unknown status.
    case other

    init(rawStatus: Int?) {
        switch rawStatus.flatMap(SCFrameStatus.init(rawValue:)) {
        case .complete?: self = .complete
        case .idle?: self = .idle
        default: self = .other
        }
    }
}

/// What the callback did with the frame.
enum FrameOutcome: Equatable, Sendable {
    case notComplete
    case enqueued
    case droppedNotReady
}

/// Cumulative (or windowed) per-callback counters.
///
/// A callback is recorded once, at exit, with `record(_:_:)`, so every window
/// satisfies `complete >= enqueued + droppedNotReady`.
struct FrameCounters: Equatable, Sendable {
    var received = 0
    var complete = 0
    var idle = 0
    var other = 0
    var enqueued = 0
    var droppedNotReady = 0
    var flushes = 0

    mutating func record(_ bucket: FrameStatusBucket, _ outcome: FrameOutcome) {
        received += 1
        switch bucket {
        case .complete: complete += 1
        case .idle: idle += 1
        case .other: other += 1
        }
        switch outcome {
        case .notComplete: break
        case .enqueued: enqueued += 1
        case .droppedNotReady: droppedNotReady += 1
        }
    }

    mutating func recordFlush() {
        flushes += 1
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(
            received: lhs.received - rhs.received, complete: lhs.complete - rhs.complete,
            idle: lhs.idle - rhs.idle, other: lhs.other - rhs.other,
            enqueued: lhs.enqueued - rhs.enqueued,
            droppedNotReady: lhs.droppedNotReady - rhs.droppedNotReady,
            flushes: lhs.flushes - rhs.flushes)
    }

    var logText: String {
        "received=\(received) complete=\(complete) idle=\(idle) other=\(other) "
            + "enqueued=\(enqueued) droppedNotReady=\(droppedNotReady) flushes=\(flushes)"
    }
}

enum FrameFlowState: String, Sendable {
    case healthy, silent, rendererBlocked, callbackStuck

    /// First match wins. Stuck means the callback has run strictly longer than the window.
    static func classify(
        window: FrameCounters, windowLength: Duration, callbackRunningFor: Duration?
    ) -> Self {
        if let running = callbackRunningFor, running > windowLength { return .callbackStuck }
        if window.received == 0 { return .silent }
        if window.complete > 0 && window.enqueued == 0 { return .rendererBlocked }
        return .healthy
    }
}

/// Only `notice` and `error` exist: `info` and `debug` are not kept on disk.
enum FrameFlowLogLevel: Equatable, Sendable {
    case notice, error
}

struct FrameFlowTick: Equatable, Sendable {
    struct Transition: Equatable, Sendable {
        var from: FrameFlowState
        var to: FrameFlowState
        /// Sum of the measured windows spent in `from`.
        var oldStateLasted: Duration
        var level: FrameFlowLogLevel
    }

    var window: FrameCounters
    var state: FrameFlowState
    var transition: Transition?
    var heartbeat: Bool
    /// True when the window contained a flush after `.failed`.
    var logsFlush: Bool
    /// Never while the callback is stuck: reading the renderer could block on
    /// the same lock the stuck callback holds, which would silence the watchdog.
    var readsRenderer: Bool
}

/// Decides what each watchdog window logs. Follows the `CaptureLifecycle` pattern.
struct FrameFlowMonitor: Sendable {
    /// Until the owner has measured whether a static region delivers `idle`
    /// callbacks, `silent` stays a fault (error level). See the README.
    static let silentIsFaultDefault = true
    /// 30 ticks of 2 s. Counting ticks keeps timer leeway from pushing it to 62 s.
    static let heartbeatEveryTicks = 30

    enum StopReason: Sendable { case requested, ended }

    private enum Phase { case notStarted, running, stopped }

    private let silentIsFault: Bool
    private var phase = Phase.notStarted
    private var lastCounters = FrameCounters()
    private var state = FrameFlowState.healthy
    private var stateLasted = Duration.zero
    private var ticks = 0

    init(silentIsFault: Bool = Self.silentIsFaultDefault) {
        self.silentIsFault = silentIsFault
    }

    var isRunning: Bool { phase == .running }

    /// True only from not started. The state before the first window is `healthy`.
    mutating func start(baseline: FrameCounters) -> Bool {
        guard phase == .notStarted else { return false }
        phase = .running
        lastCounters = baseline
        return true
    }

    /// Nil unless running.
    mutating func tick(
        counters: FrameCounters, windowLength: Duration, callbackRunningFor: Duration?
    ) -> FrameFlowTick? {
        guard phase == .running else { return nil }
        let window = counters - lastCounters
        lastCounters = counters
        ticks += 1

        let new = FrameFlowState.classify(
            window: window, windowLength: windowLength, callbackRunningFor: callbackRunningFor)
        var transition: FrameFlowTick.Transition?
        if new == state {
            stateLasted += windowLength
        } else {
            transition = .init(
                from: state, to: new, oldStateLasted: stateLasted, level: level(into: new))
            state = new
            // The window that causes a change belongs to the new state.
            stateLasted = windowLength
        }
        let heartbeat = ticks % Self.heartbeatEveryTicks == 0
        return FrameFlowTick(
            window: window, state: new, transition: transition, heartbeat: heartbeat,
            logsFlush: window.flushes > 0,
            readsRenderer: (transition != nil || heartbeat) && new != .callbackStuck)
    }

    /// Whether the caller should log the stop line. A request logs only when
    /// running; a stream end logs unless already stopped. Always ends stopped
    /// when it returns true.
    mutating func stop(_ reason: StopReason) -> Bool {
        switch (reason, phase) {
        case (.requested, .running), (.ended, .notStarted), (.ended, .running):
            phase = .stopped
            return true
        default:
            return false
        }
    }

    private func level(into new: FrameFlowState) -> FrameFlowLogLevel {
        switch new {
        case .healthy: .notice
        case .silent: silentIsFault ? .error : .notice
        case .rendererBlocked, .callbackStuck: .error
        }
    }
}

/// What the capture was started with, for the start line.
struct CaptureStartInfo: Equatable, Sendable {
    var displayID: CGDirectDisplayID
    var sourceRect: CGRect
    var width: Int
    var height: Int
    var framesPerSecond: Int
}

/// The renderer fields worth logging, already reduced to plain values.
struct RendererSnapshot: Equatable, Sendable {
    var statusRawValue: Int
    /// "domain code description", nil when there is no error.
    var error: String?
    var isReady: Bool
    var requiresFlush: Bool

    static func statusName(_ rawValue: Int) -> String {
        switch rawValue {
        case 0: "unknown"
        case 1: "rendering"
        case 2: "failed"
        default: "raw \(rawValue)"
        }
    }

    var logText: String {
        "status=\(Self.statusName(statusRawValue)) error=\(error ?? "none") "
            + "ready=\(isReady) requiresFlush=\(requiresFlush)"
    }
}

/// Builds each log line as one String. Stable keys, so they are easy to grep.
enum FrameFlowLog {
    static let callbackInFlight = "not read (callback in flight)"

    static func started(_ info: CaptureStartInfo) -> String {
        let rect = info.sourceRect
        let text = String(
            format: "%g,%g,%g,%g", rect.origin.x, rect.origin.y, rect.width, rect.height)
        return "capture started display=\(info.displayID) sourceRect=\(text) "
            + "output=\(info.width)x\(info.height) fps=\(info.framesPerSecond)"
    }

    static func stopped(total: FrameCounters) -> String {
        "capture stopped by request total: \(total.logText)"
    }

    static func streamEnded(
        domain: String, code: Int, description: String, total: FrameCounters
    ) -> String {
        "stream ended by itself domain=\(domain) code=\(code) description=\(description) "
            + "total: \(total.logText)"
    }

    static func stateChange(
        _ transition: FrameFlowTick.Transition, window: FrameCounters, renderer: String
    ) -> String {
        "frame flow \(transition.from.rawValue) -> \(transition.to.rawValue) "
            + "after \(seconds(transition.oldStateLasted)) s window: \(window.logText) "
            + "renderer: \(renderer)"
    }

    static func heartbeat(state: FrameFlowState, total: FrameCounters, renderer: String) -> String {
        "heartbeat state=\(state.rawValue) total: \(total.logText) renderer: \(renderer)"
    }

    static func flushed(flushes: Int, error: String?) -> String {
        "renderer flushed after failed flushes=\(flushes) error=\(error ?? "none")"
    }

    /// One decimal, truncated.
    private static func seconds(_ duration: Duration) -> String {
        let (whole, attoseconds) = duration.components
        let tenths = whole * 10 + attoseconds / 100_000_000_000_000_000
        return "\(tenths / 10).\(tenths % 10)"
    }
}

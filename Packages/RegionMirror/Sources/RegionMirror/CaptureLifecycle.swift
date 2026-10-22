import CoreGraphics

/// Identifies one `start()` attempt. Issued by ``CaptureLifecycle/beginStart()``;
/// never reused, so a stale token can never match a newer start.
struct CaptureToken: Hashable, Sendable {
    fileprivate let value: UInt64
}

/// Result of ``CaptureLifecycle/regionUpdate(_:)``.
enum RegionUpdateDecision<Stream> {
    /// No capture is starting or running.
    case notRunning
    /// A start is in flight; the rect was stored and the start applies it.
    case deferred
    /// Apply the region to this running stream now.
    case apply(Stream)
}

extension RegionUpdateDecision: Equatable where Stream: Equatable {}

/// Serializes `start()` / `stop()` / stream-ended events of `RegionCapture`.
///
/// Pure value logic so the races are unit-tested without ScreenCaptureKit.
/// `Stream` is whatever the capture needs to tear down (`SCStream` plus its
/// output in production, `String` in tests).
///
/// The main actor can re-enter during every `await` of a start, so each start
/// carries a token and every continuation re-checks it. There is deliberately
/// no `stopping` phase: ``stop()`` moves to idle synchronously and the caller
/// tears down the stream it got back.
///
/// A start owns the lifecycle until it resolves (``commit(_:stream:)``,
/// ``startFailed(_:)`` or ``stop()``). A stream that ends by itself during its
/// start does not free the lifecycle: the phase stays `starting`, marked ended
/// and holding the error, so no second start can slip in and make the first
/// one lose that error.
struct CaptureLifecycle<Stream> {
    enum Phase {
        case idle
        /// `endedError` is non-nil once the start's stream ended by itself; the
        /// start is then no longer current and only waits to throw that error.
        case starting(CaptureToken, endedError: RegionMirrorError?)
        case running(CaptureToken, Stream)
    }

    private(set) var phase: Phase = .idle
    private var pendingSourceRect: CGRect?
    private var lastToken: UInt64 = 0

    /// The stream while running, otherwise nil.
    var runningStream: Stream? {
        if case .running(_, let stream) = phase { return stream }
        return nil
    }

    /// idle -> starting. Returns nil when a start (ended or not, until it
    /// resolves) or a capture already exists (the caller throws `.alreadyRunning`).
    mutating func beginStart() -> CaptureToken? {
        guard case .idle = phase else { return nil }
        lastToken += 1
        let token = CaptureToken(value: lastToken)
        pendingSourceRect = nil
        phase = .starting(token, endedError: nil)
        return token
    }

    /// True only while `token`'s start is in flight and its stream has not
    /// ended. An ended start is not current, so its settle loop and
    /// ``commit(_:stream:)`` give up.
    func isCurrent(_ token: CaptureToken) -> Bool {
        if case .starting(let current, nil) = phase { return current == token }
        return false
    }

    /// True while `token`'s start has not resolved, whether or not its stream
    /// ended. False once ``stop()``, ``startFailed(_:)`` or ``commit(_:stream:)``
    /// resolved it, and for a stale token. After a failed await a start asks
    /// this to tell "stop() cancelled me" (false) from "I still own the
    /// lifecycle" (true).
    func isStarting(_ token: CaptureToken) -> Bool {
        if case .starting(let current, _) = phase { return current == token }
        return false
    }

    /// True when a region update can matter: a live start (stream not ended) or
    /// a running capture. False when idle or when the start's stream ended, so
    /// callers can answer `.notRunning` before doing any other work.
    var acceptsRegionUpdates: Bool {
        switch phase {
        case .idle, .starting(_, .some): return false
        case .starting(_, .none), .running: return true
        }
    }

    /// Routes a region update by phase. While starting, stores `sourceRect`
    /// (latest wins) for ``takePendingRegion(_:)``. A start whose stream already
    /// ended is `.notRunning` and stores nothing: that start only throws.
    mutating func regionUpdate(_ sourceRect: CGRect) -> RegionUpdateDecision<Stream> {
        switch phase {
        case .idle:
            return .notRunning
        case .starting(_, let endedError):
            if endedError != nil { return .notRunning }
            pendingSourceRect = sourceRect
            return .deferred
        case .running(_, let stream):
            return .apply(stream)
        }
    }

    /// One-shot: the stored region of `token`'s start, nil for a stale token
    /// or when nothing is pending.
    mutating func takePendingRegion(_ token: CaptureToken) -> CGRect? {
        guard isCurrent(token) else { return nil }
        defer { pendingSourceRect = nil }
        return pendingSourceRect
    }

    /// starting(token) -> running. False when the start was cancelled or
    /// superseded; the caller then tears `stream` down itself.
    mutating func commit(_ token: CaptureToken, stream: Stream) -> Bool {
        guard isCurrent(token) else { return false }
        pendingSourceRect = nil
        phase = .running(token, stream)
        return true
    }

    /// Goes idle if `token`'s start is still unresolved, ended or not (this
    /// releases an ended start); otherwise no change.
    mutating func startFailed(_ token: CaptureToken) {
        guard case .starting(let current, _) = phase, current == token else { return }
        pendingSourceRect = nil
        phase = .idle
    }

    /// Always ends idle with nothing pending. Returns the stream to tear down
    /// when one was running; a starting capture is cancelled (its own
    /// `start()` stops the stream it created). A cancellation wins over an
    /// error recorded by ``streamEnded(_:error:)``: the record is cleared with
    /// the phase.
    mutating func stop() -> Stream? {
        let stream = runningStream
        pendingSourceRect = nil
        phase = .idle
        return stream
    }

    /// The error that ended `token`'s start by itself. Readable until that
    /// start resolves (``startFailed(_:)``) or ``stop()`` cancels it; nil
    /// afterwards. Once `token` is no longer current, a start reads this to
    /// tell "the stream died" (throw the error) from "stop() cancelled me"
    /// (throw `.notRunning`).
    func endedError(for token: CaptureToken) -> RegionMirrorError? {
        if case .starting(let current, let error?) = phase, current == token { return error }
        return nil
    }

    /// The stream of `token` ended by itself with `error`. Returns true only
    /// when it was the running stream (the caller reports `onStop`). A start in
    /// flight stays `starting`, marked ended with `error` for
    /// ``endedError(for:)`` (first error wins), without a report; any other
    /// token changes nothing.
    mutating func streamEnded(_ token: CaptureToken, error: RegionMirrorError) -> Bool {
        switch phase {
        case .running(let current, _) where current == token:
            phase = .idle
            return true
        case .starting(let current, nil) where current == token:
            pendingSourceRect = nil
            phase = .starting(current, endedError: error)
            return false
        default:
            return false
        }
    }
}

extension CaptureLifecycle.Phase: Equatable where Stream: Equatable {}

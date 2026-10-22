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
struct CaptureLifecycle<Stream> {
    enum Phase {
        case idle
        case starting(CaptureToken)
        case running(CaptureToken, Stream)
    }

    private(set) var phase: Phase = .idle
    private var pendingSourceRect: CGRect?
    private var lastToken: UInt64 = 0
    /// Why a start ended by itself, keyed by that start's token.
    private var endedDuringStart: (token: CaptureToken, error: RegionMirrorError)?

    /// The stream while running, otherwise nil.
    var runningStream: Stream? {
        if case .running(_, let stream) = phase { return stream }
        return nil
    }

    /// idle -> starting. Returns nil when a start or a capture already exists
    /// (the caller throws `.alreadyRunning`).
    mutating func beginStart() -> CaptureToken? {
        guard case .idle = phase else { return nil }
        lastToken += 1
        let token = CaptureToken(value: lastToken)
        pendingSourceRect = nil
        endedDuringStart = nil
        phase = .starting(token)
        return token
    }

    /// True only while `token`'s start is still in flight.
    func isCurrent(_ token: CaptureToken) -> Bool {
        if case .starting(let current) = phase { return current == token }
        return false
    }

    /// Routes a region update by phase. While starting, stores `sourceRect`
    /// (latest wins) for ``takePendingRegion(_:)``.
    mutating func regionUpdate(_ sourceRect: CGRect) -> RegionUpdateDecision<Stream> {
        switch phase {
        case .idle:
            return .notRunning
        case .starting:
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

    /// Goes idle if `token`'s start is still in flight; otherwise no change.
    mutating func startFailed(_ token: CaptureToken) {
        guard isCurrent(token) else { return }
        pendingSourceRect = nil
        phase = .idle
    }

    /// Always ends idle with nothing pending. Returns the stream to tear down
    /// when one was running; a starting capture is cancelled (its own
    /// `start()` stops the stream it created). A cancellation wins over an
    /// error recorded by ``streamEnded(_:error:)``.
    mutating func stop() -> Stream? {
        let stream = runningStream
        pendingSourceRect = nil
        endedDuringStart = nil
        phase = .idle
        return stream
    }

    /// The error that ended `token`'s start by itself, nil when that start was
    /// cancelled by ``stop()`` or superseded. Once `token` is no longer current,
    /// a start reads this to tell "the stream died" (throw the error) from
    /// "stop() cancelled me" (throw `.notRunning`).
    func endedError(for token: CaptureToken) -> RegionMirrorError? {
        guard let ended = endedDuringStart, ended.token == token else { return nil }
        return ended.error
    }

    /// The stream of `token` ended by itself with `error`. Returns true only
    /// when it was the running stream (the caller reports `onStop`). A start in
    /// flight goes idle without a report and keeps `error` for
    /// ``endedError(for:)``; any other token changes nothing.
    mutating func streamEnded(_ token: CaptureToken, error: RegionMirrorError) -> Bool {
        switch phase {
        case .running(let current, _) where current == token:
            phase = .idle
            return true
        case .starting(let current) where current == token:
            pendingSourceRect = nil
            endedDuringStart = (token, error)
            phase = .idle
            return false
        default:
            return false
        }
    }
}

extension CaptureLifecycle.Phase: Equatable where Stream: Equatable {}

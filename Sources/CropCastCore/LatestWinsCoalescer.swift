/// Keeps at most one asynchronous update in flight and remembers only the
/// newest value submitted meanwhile. Pure state, no concurrency of its own:
/// the caller performs the work and reports back with `complete()`.
///
/// Usage: `begin()` when the session's first operation (the capture start)
/// begins. Then, for every change, `submit(_:)`; a non-nil result must be sent
/// now. When any send finishes, `complete()`; a non-nil result must be sent next.
public struct LatestWinsCoalescer<Value: Sendable>: Sendable {
    private var isActive = false
    private var isBusy = false
    private var pending: Value?

    public init() {}

    /// Activates the coalescer and marks the first operation (the capture
    /// `start`) as in flight, so changes arriving during it are queued.
    public mutating func begin() {
        isActive = true
        isBusy = true
        pending = nil
    }

    /// Returns the value to send now, or nil if it was queued or ignored
    /// (before `begin()` or after `reset()`).
    public mutating func submit(_ value: Value) -> Value? {
        guard isActive else { return nil }
        if isBusy {
            pending = value
            return nil
        }
        isBusy = true
        return value
    }

    /// The operation in flight finished. Returns the newest queued value,
    /// which is now in flight, or nil if nothing is waiting.
    public mutating func complete() -> Value? {
        guard isActive else { return nil }
        if let next = pending {
            pending = nil
            return next
        }
        isBusy = false
        return nil
    }

    /// Drops everything and ignores further submits until `begin()`.
    public mutating func reset() {
        isActive = false
        isBusy = false
        pending = nil
    }
}

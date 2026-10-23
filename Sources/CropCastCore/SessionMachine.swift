public enum SessionPhase: Sendable, Equatable {
    case idle, starting, sharing, stopping
}

extension SessionPhase {
    /// True from the start request until the session is fully stopped
    /// (Starting…, Sharing and Stopping…). The frame is red and the menu bar
    /// icon badged exactly while this holds.
    public var isLive: Bool {
        switch self {
        case .idle: false
        case .starting, .sharing, .stopping: true
        }
    }
}

public enum SessionEvent: Sendable, Equatable {
    /// The user chose Start/Stop Sharing.
    case toggleSharing
    /// The app was asked to quit (⌘Q, menu, system).
    case quitRequested
    case startSucceeded
    /// A start step failed and everything already started was rolled back.
    case startFailed
    /// The capture start was cancelled (not an error): rolled back, no alert.
    case startCancelled
    case stopCompleted
}

/// What the glue has to do after an event.
public enum SessionEffect: Sendable, Equatable {
    case startSession
    case stopSession
    case showStartFailure
    /// Quit may proceed: nothing is running any more.
    case terminate
}

/// The sharing session as a pure reducer: `idle -> starting -> sharing ->
/// stopping -> idle`, plus a quit that waits for whatever is in progress.
/// Events that do not fit the current phase are ignored.
public struct SessionMachine: Sendable, Equatable {
    public internal(set) var phase: SessionPhase = .idle
    public internal(set) var quitPending = false

    public init() {}

    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        switch (phase, event) {
        case (.idle, .toggleSharing) where !quitPending:
            phase = .starting
            return [.startSession]
        case (.sharing, .toggleSharing) where !quitPending:
            phase = .stopping
            return [.stopSession]

        case (.idle, .quitRequested):
            quitPending = true
            return [.terminate]
        case (.sharing, .quitRequested):
            guard !quitPending else { return [] }
            quitPending = true
            phase = .stopping
            return [.stopSession]
        case (.starting, .quitRequested), (.stopping, .quitRequested):
            quitPending = true
            return []

        case (.starting, .startSucceeded):
            if quitPending {
                phase = .stopping
                return [.stopSession]
            }
            phase = .sharing
            return []
        case (.starting, .startFailed):
            phase = .idle
            return [quitPending ? .terminate : .showStartFailure]
        case (.starting, .startCancelled):
            phase = .idle
            return quitPending ? [.terminate] : []
        case (.stopping, .stopCompleted):
            phase = .idle
            return quitPending ? [.terminate] : []

        default:
            return []
        }
    }
}

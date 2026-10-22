/// The steps of Start Sharing, in the order they run.
public enum StartStepID: CaseIterable, Sendable, Equatable {
    case permission, display, screen, mirror, frame, capture

    /// Used in the failure alert: "CropCast could not <title>".
    public var title: String {
        switch self {
        case .permission: return "get Screen Recording permission"
        case .display: return "create the virtual display"
        case .screen: return "wait for the virtual display to appear as a screen"
        case .mirror: return "open the mirror window"
        case .frame: return "show the frame"
        case .capture: return "start capturing"
        }
    }
}

/// Why an undo runs: a failed start rolls back, a stop or quit tears down.
public enum UnwindReason: Sendable, Equatable {
    case rollback, stop
}

/// Thrown by a step to say the start was cancelled. Not an error to show.
public struct StartCancelled: Error, Equatable, Sendable {
    public init() {}
}

public typealias StartUndo = @MainActor (UnwindReason) async -> Void

/// One start step. `run` returns how to undo its effect, or nil if it has none.
public struct StartStep: Sendable {
    public let id: StartStepID
    public let run: @MainActor () async throws -> StartUndo?

    public init(id: StartStepID, run: @escaping @MainActor () async throws -> StartUndo?) {
        self.id = id
        self.run = run
    }
}

public enum StartOutcome: Sendable {
    case started
    /// `step` threw `error`; everything started before it was rolled back.
    case failed(step: StartStepID, error: any Error)
    /// `step` threw `StartCancelled`; everything started before it was rolled back.
    case cancelled(step: StartStepID)
}

/// Runs the start steps with one undo stack: all-or-nothing on failure, and
/// `teardown()` unwinds a running session in reverse. Both are safe to repeat.
@MainActor
public final class StartSequence {
    private let steps: [StartStep]
    private var undos: [StartUndo] = []

    public init(steps: [StartStep]) {
        self.steps = steps
    }

    public func run() async -> StartOutcome {
        for step in steps {
            do {
                if let undo = try await step.run() { undos.append(undo) }
            } catch {
                await unwind(.rollback)
                if error is StartCancelled { return .cancelled(step: step.id) }
                return .failed(step: step.id, error: error)
            }
        }
        return .started
    }

    /// Stops a running session: the undos run in reverse order. Idempotent.
    public func teardown() async {
        await unwind(.stop)
    }

    private func unwind(_ reason: UnwindReason) async {
        while let undo = undos.popLast() {
            await undo(reason)
        }
    }
}

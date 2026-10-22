import Testing
@testable import CropCastCore

private struct Boom: Error, Equatable {}

@MainActor
private final class Recorder {
    var log: [String] = []
    /// Steps that fail (throw `Boom`) or cancel (throw `StartCancelled`).
    var failAt: StartStepID?
    var cancelAt: StartStepID?

    func steps() -> [StartStep] {
        StartStepID.allCases.map { id in
            StartStep(id: id) { [self] in
                log.append("run \(id)")
                if failAt == id { throw Boom() }
                if cancelAt == id { throw StartCancelled() }
                // The permission gate has nothing to undo.
                guard id != .permission else { return nil }
                return { [self] reason in log.append("undo \(id) \(reason)") }
            }
        }
    }
}

@MainActor
@Suite("StartSequence")
struct StartSequenceTests {
    private static let order: [StartStepID] = [.permission, .display, .screen, .mirror, .frame, .capture]

    @Test func stepsRunInTheAgreedOrder() {
        #expect(StartStepID.allCases == Self.order)
    }

    @Test func successRunsEveryStepInOrderAndKeepsThemRunning() async {
        let r = Recorder()
        let outcome = await StartSequence(steps: r.steps()).run()
        guard case .started = outcome else { Issue.record("expected .started, got \(outcome)"); return }
        #expect(r.log == Self.order.map { "run \($0)" })
    }

    @Test(arguments: StartStepID.allCases)
    func failureAtAnyStepUnwindsEarlierStepsInReverse(failing: StartStepID) async {
        let r = Recorder()
        r.failAt = failing
        let outcome = await StartSequence(steps: r.steps()).run()

        guard case let .failed(step, error) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(step == failing)
        #expect(error is Boom)

        let index = Self.order.firstIndex(of: failing)!
        let ran = Self.order[...index].map { "run \($0)" }
        let undone = Self.order[..<index].reversed()
            .filter { $0 != .permission }
            .map { "undo \($0) rollback" }
        #expect(r.log == ran + undone)
    }

    @Test func aFailedStepIsNotUndoneItself() async {
        let r = Recorder()
        r.failAt = .capture
        _ = await StartSequence(steps: r.steps()).run()
        #expect(!r.log.contains("undo capture rollback"))
        #expect(r.log.last == "undo display rollback")
    }

    @Test func cancellationUnwindsLikeAFailureButIsReportedSeparately() async {
        let r = Recorder()
        r.cancelAt = .capture
        let outcome = await StartSequence(steps: r.steps()).run()
        guard case let .cancelled(step) = outcome else {
            Issue.record("expected .cancelled, got \(outcome)")
            return
        }
        #expect(step == .capture)
        #expect(r.log.suffix(4) == [
            "undo frame rollback", "undo mirror rollback", "undo screen rollback", "undo display rollback",
        ])
    }

    @Test func teardownUnwindsEverythingInReverseWithTheStopReason() async {
        let r = Recorder()
        let sequence = StartSequence(steps: r.steps())
        _ = await sequence.run()
        r.log.removeAll()
        await sequence.teardown()
        #expect(r.log == [
            "undo capture stop", "undo frame stop", "undo mirror stop",
            "undo screen stop", "undo display stop",
        ])
    }

    @Test func teardownIsIdempotent() async {
        let r = Recorder()
        let sequence = StartSequence(steps: r.steps())
        _ = await sequence.run()
        await sequence.teardown()
        r.log.removeAll()
        await sequence.teardown()
        #expect(r.log.isEmpty)
    }

    @Test func teardownAfterAFailedStartDoesNothingMore() async {
        let r = Recorder()
        r.failAt = .frame
        let sequence = StartSequence(steps: r.steps())
        _ = await sequence.run()
        r.log.removeAll()
        await sequence.teardown()
        #expect(r.log.isEmpty)
    }

    @Test func teardownBeforeRunDoesNothing() async {
        let r = Recorder()
        await StartSequence(steps: r.steps()).teardown()
        #expect(r.log.isEmpty)
    }
}

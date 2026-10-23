import Testing
@testable import CropCastCore

@Suite("SessionMachine")
struct SessionMachineTests {
    private func machine(in phase: SessionPhase, quitPending: Bool = false) -> SessionMachine {
        var m = SessionMachine()
        m.phase = phase
        m.quitPending = quitPending
        return m
    }

    // MARK: Toggle

    @Test func startsIdle() {
        let m = SessionMachine()
        #expect(m.phase == .idle)
        #expect(m.quitPending == false)
    }

    @Test func toggleWhileIdleStarts() {
        var m = machine(in: .idle)
        #expect(m.handle(.toggleSharing) == [.startSession])
        #expect(m.phase == .starting)
    }

    @Test func toggleWhileSharingStops() {
        var m = machine(in: .sharing)
        #expect(m.handle(.toggleSharing) == [.stopSession])
        #expect(m.phase == .stopping)
    }

    @Test(arguments: [SessionPhase.starting, .stopping])
    func toggleIsIgnoredWhileBusy(phase: SessionPhase) {
        var m = machine(in: phase)
        #expect(m.handle(.toggleSharing) == [])
        #expect(m.phase == phase)
    }

    @Test func toggleIsIgnoredOnceQuitIsPending() {
        var m = machine(in: .sharing, quitPending: true)
        #expect(m.handle(.toggleSharing) == [])
        #expect(m.phase == .sharing)
    }

    // MARK: Start outcome

    @Test func startSucceededMovesToSharing() {
        var m = machine(in: .starting)
        #expect(m.handle(.startSucceeded) == [])
        #expect(m.phase == .sharing)
    }

    @Test func startFailedReturnsToIdleAndAlerts() {
        var m = machine(in: .starting)
        #expect(m.handle(.startFailed) == [.showStartFailure])
        #expect(m.phase == .idle)
    }

    @Test func startCancelledReturnsToIdleWithoutAlert() {
        var m = machine(in: .starting)
        #expect(m.handle(.startCancelled) == [])
        #expect(m.phase == .idle)
    }

    // MARK: Stop outcome

    @Test func stopCompletedReturnsToIdle() {
        var m = machine(in: .stopping)
        #expect(m.handle(.stopCompleted) == [])
        #expect(m.phase == .idle)
    }

    // MARK: Quit

    @Test func quitWhileIdleTerminatesAtOnce() {
        var m = machine(in: .idle)
        #expect(m.handle(.quitRequested) == [.terminate])
    }

    @Test func quitWhileSharingStopsThenTerminates() {
        var m = machine(in: .sharing)
        #expect(m.handle(.quitRequested) == [.stopSession])
        #expect(m.phase == .stopping)
        #expect(m.quitPending)
        #expect(m.handle(.stopCompleted) == [.terminate])
        #expect(m.phase == .idle)
    }

    @Test func quitWhileStartingWaitsThenTearsDown() {
        var m = machine(in: .starting)
        #expect(m.handle(.quitRequested) == [])
        #expect(m.phase == .starting)
        #expect(m.quitPending)
        #expect(m.handle(.startSucceeded) == [.stopSession])
        #expect(m.phase == .stopping)
        #expect(m.handle(.stopCompleted) == [.terminate])
    }

    @Test func startFailureWhileQuittingSkipsTheAlert() {
        var m = machine(in: .starting, quitPending: true)
        #expect(m.handle(.startFailed) == [.terminate])
        #expect(m.phase == .idle)
    }

    @Test func startCancelledWhileQuittingTerminates() {
        var m = machine(in: .starting, quitPending: true)
        #expect(m.handle(.startCancelled) == [.terminate])
        #expect(m.phase == .idle)
    }

    @Test func quitWhileStoppingTerminatesAfterTheStop() {
        var m = machine(in: .stopping)
        #expect(m.handle(.quitRequested) == [])
        #expect(m.handle(.stopCompleted) == [.terminate])
    }

    @Test func repeatedQuitRequestsDoNotRepeatEffects() {
        var m = machine(in: .sharing)
        #expect(m.handle(.quitRequested) == [.stopSession])
        #expect(m.handle(.quitRequested) == [])
    }

    // MARK: Stray events

    @Test func outcomesInTheWrongPhaseAreIgnored() {
        var idle = machine(in: .idle)
        #expect(idle.handle(.startSucceeded) == [])
        #expect(idle.handle(.startFailed) == [])
        #expect(idle.handle(.startCancelled) == [])
        #expect(idle.handle(.stopCompleted) == [])
        #expect(idle.phase == .idle)

        var sharing = machine(in: .sharing)
        #expect(sharing.handle(.startFailed) == [])
        #expect(sharing.handle(.stopCompleted) == [])
        #expect(sharing.phase == .sharing)
    }

    // MARK: Live

    @Test(arguments: [
        (SessionPhase.idle, false), (.starting, true), (.sharing, true), (.stopping, true),
    ])
    func isLiveCoversEveryPhaseExceptIdle(phase: SessionPhase, expected: Bool) {
        #expect(phase.isLive == expected)
    }

    @Test func liveFollowsThePhaseThroughStartFailureShareAndQuit() {
        var m = SessionMachine()
        #expect(m.phase.isLive == false)

        _ = m.handle(.toggleSharing)
        #expect(m.phase.isLive == true)
        _ = m.handle(.startFailed)
        #expect(m.phase.isLive == false)

        _ = m.handle(.toggleSharing)
        #expect(m.phase.isLive == true)
        _ = m.handle(.startCancelled)
        #expect(m.phase.isLive == false)

        _ = m.handle(.toggleSharing)
        _ = m.handle(.startSucceeded)
        #expect(m.phase == .sharing)
        #expect(m.phase.isLive == true)
        _ = m.handle(.quitRequested)
        #expect(m.phase == .stopping)
        #expect(m.phase.isLive == true)
        _ = m.handle(.stopCompleted)
        #expect(m.phase.isLive == false)
    }
}

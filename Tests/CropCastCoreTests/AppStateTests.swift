import Foundation
import Testing
@testable import CropCastCore

@Suite("AppState")
struct AppStateTests {
    private func titles(_ state: AppState) -> [String] {
        state.menuEntries().compactMap {
            if case let .item(title, _) = $0 { return title }
            return nil
        }
    }

    @Test func defaultStateIsIdle() {
        let state = AppState()
        #expect(state.phase == .idle)
        #expect(state.isSharing == false)
        #expect(state.isFrameVisible == false)
        #expect(state.lastPreset == nil)
        #expect(titles(state).contains("Start Sharing"))
        #expect(titles(state).contains("Show Frame"))
    }

    @Test func toggleFrameFlipsVisibilityAndTitle() {
        var state = AppState()
        state.apply(.toggleFrame)
        #expect(state.isFrameVisible == true)
        #expect(state.isSharing == false)
        #expect(titles(state).contains("Hide Frame"))
        #expect(!titles(state).contains("Show Frame"))
    }

    @Test func toggleSharingWalksTheSessionPhasesAndTitles() {
        var state = AppState()
        #expect(state.apply(.toggleSharing) == [.startSession])
        #expect(state.phase == .starting)
        #expect(titles(state).first == "Starting…")
        #expect(state.isFrameVisible == false)

        state.handle(.startSucceeded)
        #expect(state.isSharing)
        #expect(titles(state).first == "Stop Sharing")

        #expect(state.apply(.toggleSharing) == [.stopSession])
        #expect(state.phase == .stopping)
        #expect(titles(state).first == "Stopping…")

        state.handle(.stopCompleted)
        #expect(state.phase == .idle)
        #expect(titles(state).first == "Start Sharing")
    }

    @Test func toggleSharingIsIgnoredWhileStartingOrStopping() {
        var state = AppState()
        state.apply(.toggleSharing)
        #expect(state.apply(.toggleSharing) == [])
        #expect(state.phase == .starting)
    }

    @Test func aFailedStartReturnsToStartSharing() {
        var state = AppState()
        state.apply(.toggleSharing)
        #expect(state.handle(.startFailed) == [.showStartFailure])
        #expect(state.phase == .idle)
        #expect(titles(state).first == "Start Sharing")
    }

    @Test func applyingTogglesTwiceRestoresStart() {
        var state = AppState()
        state.apply(.toggleFrame)
        state.apply(.toggleFrame)
        state.apply(.toggleSharing)
        state.handle(.startSucceeded)
        state.apply(.toggleSharing)
        state.handle(.stopCompleted)
        #expect(state == AppState())
    }

    @Test(arguments: FramePreset.allCases)
    func selectPresetOnlySetsLastPreset(preset: FramePreset) {
        var state = AppState()
        state.apply(.selectPreset(preset))
        #expect(state.lastPreset == preset)
        #expect(state.isSharing == false)
        #expect(state.isFrameVisible == false)
    }

    @Test func quitDoesNotChangeState() {
        var state = AppState()
        state.apply(.toggleFrame)
        let before = state
        #expect(state.apply(.quit) == [])
        #expect(state == before)
    }

    @Test func quitRequestedWhileSharingStopsThenTerminates() {
        var state = AppState()
        state.apply(.toggleSharing)
        state.handle(.startSucceeded)
        #expect(state.handle(.quitRequested) == [.stopSession])
        #expect(state.handle(.stopCompleted) == [.terminate])
    }

    @Test func menuEntriesListEveryItemInOrder() {
        let entries = AppState().menuEntries()
        #expect(entries == [
            .item(title: "Start Sharing", action: .toggleSharing),
            .item(title: "Show Frame", action: .toggleFrame),
            .separator,
            .submenu(title: "Presets", entries: [
                .item(title: "Left", action: .selectPreset(.left)),
                .item(title: "Center", action: .selectPreset(.center)),
                .item(title: "Right", action: .selectPreset(.right)),
            ]),
            .separator,
            .item(title: "Quit CropCast", action: .quit),
        ])
    }
}

@Suite("StartFailureMessage")
struct StartFailureMessageTests {
    private struct Described: Error, LocalizedError {
        var errorDescription: String? { "the described reason" }
    }
    private struct Plain: Error {}

    @Test func usesTheLocalizedDescriptionWhenThereIsOne() {
        let text = StartFailureMessage.make(step: .display, error: Described())
        #expect(text == "CropCast could not create the virtual display.\n\nthe described reason")
    }

    @Test func fallsBackToTheErrorDump() {
        let text = StartFailureMessage.make(step: .capture, error: Plain())
        #expect(text == "CropCast could not start capturing.\n\nPlain()")
    }

    @Test(arguments: StartStepID.allCases)
    func everyStepHasADistinctTitle(step: StartStepID) {
        let others = StartStepID.allCases.filter { $0 != step }
        #expect(!others.contains { $0.title == step.title })
    }
}

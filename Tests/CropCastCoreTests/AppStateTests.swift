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

    @Test func toggleSharingFlipsSharingAndTitle() {
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
        let displays = [display(1, "Built-in", 1512), display(2, "Ultrawide", 5120)]
        let entries = AppState().menuEntries(displays: displays)
        #expect(entries == [
            .item(title: "Start Sharing", action: .toggleSharing),
            .item(title: "Show Frame", action: .toggleFrame),
            .separator,
            .submenu(title: "Display", entries: [
                .checkable(title: "Built-in", action: .selectDisplay(key: "key1"), isChecked: false),
                .checkable(title: "Ultrawide", action: .selectDisplay(key: "key2"), isChecked: true),
            ]),
            .submenu(title: "Presets", entries: [
                .item(title: "Left", action: .selectPreset(.left)),
                .item(title: "Center", action: .selectPreset(.center)),
                .item(title: "Right", action: .selectPreset(.right)),
            ]),
            .separator,
            .item(title: "Quit CropCast", action: .quit),
        ])
    }

    // MARK: Display submenu

    private func display(_ id: UInt32, _ name: String, _ width: Double) -> DisplayCandidate {
        DisplayCandidate(id: id, key: "key\(id)", name: name, width: width)
    }

    private func displayEntries(_ state: AppState, _ displays: [DisplayCandidate], excluding: Set<UInt32> = [])
        -> (isEnabled: Bool, rows: [(title: String, key: String, isChecked: Bool)])?
    {
        for entry in state.menuEntries(displays: displays, excluding: excluding) {
            guard case let .submenu("Display", entries, isEnabled) = entry else { continue }
            let rows = entries.compactMap { row -> (String, String, Bool)? in
                guard case let .checkable(title, .selectDisplay(key), isChecked) = row else { return nil }
                return (title, key, isChecked)
            }
            return (isEnabled, rows.map { (title: $0.0, key: $0.1, isChecked: $0.2) })
        }
        return nil
    }

    private let twoDisplays = [
        DisplayCandidate(id: 1, key: "key1", name: "Built-in", width: 1512),
        DisplayCandidate(id: 2, key: "key2", name: "Ultrawide", width: 5120),
    ]

    @Test func displayMenuIsEnabledOnlyWhenIdle() {
        var state = AppState()
        #expect(state.canChooseDisplay)
        #expect(displayEntries(state, twoDisplays)?.isEnabled == true)

        state.apply(.toggleSharing)
        #expect(state.phase == .starting)
        #expect(!state.canChooseDisplay)
        #expect(displayEntries(state, twoDisplays)?.isEnabled == false)

        state.handle(.startSucceeded)
        #expect(!state.canChooseDisplay)
        #expect(displayEntries(state, twoDisplays)?.isEnabled == false)

        state.apply(.toggleSharing)
        #expect(state.phase == .stopping)
        #expect(!state.canChooseDisplay)
        #expect(displayEntries(state, twoDisplays)?.isEnabled == false)

        state.handle(.stopCompleted)
        #expect(state.canChooseDisplay)
        #expect(displayEntries(state, twoDisplays)?.isEnabled == true)
    }

    @Test func displayMenuListsNamesInInputOrderWithoutExcludedIds() {
        let displays = [
            display(5, "Zeta", 1000), display(9, "CropCast", 9000), display(3, "Alpha", 2000),
        ]
        let menu = displayEntries(AppState(), displays, excluding: [9])
        #expect(menu?.rows.map(\.title) == ["Zeta", "Alpha"])
        #expect(menu?.rows.map(\.key) == ["key5", "key3"])
    }

    @Test func checkmarkIsOnTheChosenDisplay() {
        var state = AppState()
        state.apply(.selectDisplay(key: "key1"))
        #expect(displayEntries(state, twoDisplays)?.rows.map(\.isChecked) == [true, false])
    }

    @Test func checkmarkIsOnTheWidestWithNoChoice() {
        #expect(displayEntries(AppState(), twoDisplays)?.rows.map(\.isChecked) == [false, true])
    }

    @Test func checkmarkIsOnTheWidestWhenTheChosenDisplayIsDisconnected() {
        let state = AppState(chosenDisplayKey: "unplugged")
        #expect(displayEntries(state, twoDisplays)?.rows.map(\.isChecked) == [false, true])
        // The choice itself survives, so the display is used again when it is back.
        #expect(state.chosenDisplayKey == "unplugged")
    }

    @Test func checkmarkNeverLandsOnAnExcludedDisplay() {
        let displays = [display(9, "CropCast", 9000)] + twoDisplays
        let state = AppState(chosenDisplayKey: "key9")
        let rows = displayEntries(state, displays, excluding: [9])?.rows
        #expect(rows?.map(\.title) == ["Built-in", "Ultrawide"])
        #expect(rows?.filter(\.isChecked).count == 1)
        #expect(rows?.map(\.isChecked) == [false, true])
    }

    @Test func exactlyOneDisplayIsCheckedWheneverThereIsOne() {
        for chosen in [nil, "key1", "key2", "unplugged"] {
            let state = AppState(chosenDisplayKey: chosen)
            #expect(displayEntries(state, twoDisplays)?.rows.filter(\.isChecked).count == 1)
        }
        #expect(displayEntries(AppState(), [])?.rows.isEmpty == true)
    }

    @Test func initWithAChosenKeyChecksThatDisplay() {
        let state = AppState(chosenDisplayKey: "key1")
        #expect(state.chosenDisplayKey == "key1")
        #expect(displayEntries(state, twoDisplays)?.rows.map(\.isChecked) == [true, false])
    }

    @Test func selectDisplayWhileIdleStoresTheKeyAndHasNoSessionEffect() {
        var state = AppState()
        #expect(state.apply(.selectDisplay(key: "key1")) == [])
        #expect(state.chosenDisplayKey == "key1")
        #expect(state.phase == .idle)
        #expect(state.isFrameVisible == false)
    }

    @Test(arguments: [SessionPhase.starting, .sharing, .stopping])
    func selectDisplayIsIgnoredOutsideIdle(phase: SessionPhase) {
        var state = AppState(chosenDisplayKey: "key2")
        state.apply(.toggleSharing)
        if phase != .starting { state.handle(.startSucceeded) }
        if phase == .stopping { state.apply(.toggleSharing) }
        #expect(state.phase == phase)
        let before = state
        #expect(state.apply(.selectDisplay(key: "key1")) == [])
        #expect(state == before)
        #expect(state.chosenDisplayKey == "key2")
    }

    @Test func nothingButSelectDisplayChangesTheChosenDisplay() {
        var state = AppState(chosenDisplayKey: "key2")
        state.apply(.toggleFrame)
        for preset in FramePreset.allCases { state.apply(.selectPreset(preset)) }
        state.apply(.toggleSharing)
        state.handle(.startSucceeded)
        state.apply(.toggleSharing)
        state.handle(.stopCompleted)
        #expect(state.chosenDisplayKey == "key2")
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

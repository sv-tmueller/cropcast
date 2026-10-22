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
        state.apply(.toggleSharing)
        #expect(state.isSharing == true)
        #expect(state.isFrameVisible == false)
        #expect(titles(state).contains("Stop Sharing"))
        #expect(!titles(state).contains("Start Sharing"))
    }

    @Test func applyingTogglesTwiceRestoresStart() {
        var state = AppState()
        state.apply(.toggleFrame)
        state.apply(.toggleFrame)
        state.apply(.toggleSharing)
        state.apply(.toggleSharing)
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
        state.apply(.quit)
        #expect(state == before)
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

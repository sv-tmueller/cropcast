import CoreGraphics
import Testing
@testable import RegionFrame

@Suite struct DisplayChoiceTests {
    private let connected: [CGDirectDisplayID] = [1, 2, 3]

    @Test func connectedRequestedDisplayWinsOverEverythingElse() {
        #expect(DisplayChoice.pick(requested: 3, connected: connected, lastSaved: 1, underMouse: 2) == 3)
    }

    @Test func unconnectedRequestedDisplayPicksNothing() {
        #expect(DisplayChoice.pick(requested: 99, connected: connected, lastSaved: 1, underMouse: 2) == nil)
    }

    @Test func withoutRequestTheLastSavedConnectedDisplayWins() {
        #expect(DisplayChoice.pick(requested: nil, connected: connected, lastSaved: 3, underMouse: 2) == 3)
    }

    @Test func withoutRequestAnUnconnectedLastSavedDisplayFallsToTheMouse() {
        #expect(DisplayChoice.pick(requested: nil, connected: connected, lastSaved: 99, underMouse: 2) == 2)
        #expect(DisplayChoice.pick(requested: nil, connected: connected, lastSaved: nil, underMouse: 2) == 2)
    }

    @Test func withoutRequestOrMouseTheFirstDisplayIsUsed() {
        #expect(DisplayChoice.pick(requested: nil, connected: connected, lastSaved: nil, underMouse: nil) == 1)
        #expect(DisplayChoice.pick(requested: nil, connected: connected, lastSaved: 99, underMouse: 98) == 1)
    }

    @Test func withoutAnyDisplayNothingIsPicked() {
        #expect(DisplayChoice.pick(requested: nil, connected: [], lastSaved: nil, underMouse: nil) == nil)
    }
}

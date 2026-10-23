import Foundation
import Testing
@testable import RegionFrame

@Suite struct FrameStyleTests {
    @Test func idleIsBlueAndLiveIsRed() {
        #expect(FrameStyle.idle.tint == .blue)
        #expect(FrameStyle.live.tint == .red)
    }

    @Test func everyStyleHasItsOwnTint() {
        let tints = FrameStyle.allCases.map(\.tint)
        #expect(tints.count == 2)
        #expect(tints[0] != tints[1])
    }

    /// Never calls `show()`, so no panel is ordered on screen.
    @MainActor
    @Test func styleOnlyRedrawsThePanels() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        var changes = 0
        overlay.regionDidChange = { _ in changes += 1 }
        let numbers = overlay.windowNumbers

        #expect(overlay.style == .idle)
        #expect(overlay.panels.count == 4)
        #expect(overlay.panels.allSatisfy { $0.borderView.style == .idle })

        overlay.style = .live
        #expect(overlay.style == .live)
        #expect(overlay.panels.allSatisfy { $0.borderView.style == .live })
        #expect(!overlay.isVisible)
        #expect(overlay.region == nil)
        #expect(overlay.windowNumbers == numbers)
        #expect(changes == 0)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") == nil)

        overlay.style = .idle
        #expect(overlay.panels.allSatisfy { $0.borderView.style == .idle })
        #expect(overlay.windowNumbers == numbers)
    }
}

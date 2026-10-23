import CoreGraphics
import Foundation
import Testing
@testable import RegionFrame

/// None of these tests calls `show()`, so no panel is ordered on screen. Mouse
/// events are fed through the panels' border view delegate, the same path a click
/// takes.
@MainActor
@Suite struct FrameLockTests {
    private let display = CGMainDisplayID()

    /// Places the frame by preset (never shown). Returns a point inside the
    /// bottom-left corner handle and a point 100pt towards the centre.
    private func placed(_ overlay: FrameOverlay) throws -> (corner: CGPoint, inward: CGPoint) {
        overlay.apply(preset: .center, on: display)
        let frame = try rect(of: overlay)
        let corner = CGPoint(x: frame.minX + 2, y: frame.minY + 2)
        return (corner, CGPoint(x: corner.x + 100, y: corner.y + 100))
    }

    private func rect(of overlay: FrameOverlay) throws -> CGRect {
        try #require(overlay.region).rect
    }

    private func delegate(_ overlay: FrameOverlay) throws -> BorderInteractionDelegate {
        try #require(overlay.panels[0].borderView.delegate)
    }

    @Test func isUnlockedByDefault() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        #expect(!overlay.isLocked)
        #expect(overlay.panels.allSatisfy { !$0.ignoresMouseEvents })
    }

    @Test func lockingOnlyMakesThePanelsClickThrough() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        var changes = 0
        overlay.regionDidChange = { _ in changes += 1 }
        let numbers = overlay.windowNumbers

        overlay.isLocked = true
        #expect(overlay.isLocked)
        #expect(overlay.panels.allSatisfy { $0.ignoresMouseEvents })
        #expect(overlay.windowNumbers == numbers)
        #expect(changes == 0)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") == nil)
        #expect(overlay.region == nil)
        #expect(!overlay.isVisible)
        #expect(overlay.panels.allSatisfy { !$0.isVisible })

        overlay.isLocked = false
        #expect(!overlay.isLocked)
        #expect(overlay.panels.allSatisfy { !$0.ignoresMouseEvents })
        #expect(overlay.windowNumbers == numbers)
        #expect(changes == 0)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") == nil)
    }

    @Test func settingTheSameValueKeepsAnInProgressDrag() throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        let (corner, inward) = try placed(overlay)
        let before = try rect(of: overlay)

        try delegate(overlay).borderMouseDown(at: corner)
        overlay.isLocked = false
        try delegate(overlay).borderMouseDragged(to: inward)
        #expect(try rect(of: overlay) != before)
    }

    @Test func lockSurvivesHideStyleAndPresetAndAPresetStillMoves() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        overlay.isLocked = true

        overlay.hide()
        overlay.style = .live
        overlay.style = .idle
        #expect(overlay.isLocked)
        #expect(overlay.panels.allSatisfy { $0.ignoresMouseEvents })

        var changes = 0
        overlay.regionDidChange = { _ in changes += 1 }
        overlay.apply(preset: .center, on: display)
        #expect(overlay.isLocked)
        #expect(overlay.panels.allSatisfy { $0.ignoresMouseEvents })
        #expect(overlay.region != nil)
        #expect(changes == 1)
    }

    @Test func cornerDragShrinksWhenUnlocked() throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        let (corner, inward) = try placed(overlay)
        let before = try rect(of: overlay)

        try delegate(overlay).borderMouseDown(at: corner)
        try delegate(overlay).borderMouseDragged(to: inward)
        #expect(try rect(of: overlay).width < before.width)
    }

    @Test func lockingMidDragCancelsTheDrag() throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        let (corner, inward) = try placed(overlay)
        let start = try rect(of: overlay)

        try delegate(overlay).borderMouseDown(at: corner)
        try delegate(overlay).borderMouseDragged(to: CGPoint(x: corner.x + 40, y: corner.y + 40))
        let afterStep = try rect(of: overlay)
        #expect(afterStep.width < start.width)

        overlay.isLocked = true
        var changes = 0
        overlay.regionDidChange = { _ in changes += 1 }
        suite.defaults.removeObject(forKey: "RegionFrame.state.v1")
        try delegate(overlay).borderMouseDragged(to: inward)
        try delegate(overlay).borderMouseUp()
        #expect(try rect(of: overlay) == afterStep)
        #expect(changes == 0)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") == nil)

        // Unlocking does not resume the cancelled drag.
        overlay.isLocked = false
        try delegate(overlay).borderMouseDragged(to: inward)
        #expect(try rect(of: overlay) == afterStep)
    }

    @Test func mouseDownWhileLockedStartsNoDrag() throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        let (corner, inward) = try placed(overlay)
        let before = try rect(of: overlay)

        overlay.isLocked = true
        try delegate(overlay).borderMouseDown(at: corner)
        overlay.isLocked = false
        try delegate(overlay).borderMouseDragged(to: inward)
        #expect(try rect(of: overlay) == before)
    }
}

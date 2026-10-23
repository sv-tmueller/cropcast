import AppKit
import Testing
@testable import RegionFrame

/// The four strips must stay one rigid frame. None of these tests calls `show()`,
/// so no panel is ordered on screen; real panels work without a run loop.
@MainActor
@Suite struct StripAttachmentTests {
    enum OutsideChange: CaseIterable {
        case move, resize, moveAndResize

        @MainActor
        func apply(to panel: NSPanel) {
            switch self {
            case .move:
                panel.setFrameOrigin(NSPoint(x: panel.frame.minX + 137, y: panel.frame.minY - 61))
            case .resize:
                panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: panel.frame.width + 211, height: panel.frame.height + 93)), display: true)
            case .moveAndResize:
                panel.setFrame(NSRect(x: panel.frame.minX - 40, y: panel.frame.minY + 77, width: 301, height: 150), display: true)
            }
        }
    }

    @Test func stripsAreFixedWindows() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)

        #expect(overlay.panels.count == 4)
        for panel in overlay.panels {
            #expect(!panel.isMovable)
            #expect(!panel.isMovableByWindowBackground)
            #expect(!panel.styleMask.contains(.resizable))
            #expect(!panel.borderView.mouseDownCanMoveWindow)
        }
    }

    @Test(arguments: 0..<4, OutsideChange.allCases)
    func outsideChangeSnapsBack(panel index: Int, change: OutsideChange) throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        overlay.apply(preset: .center, on: CGMainDisplayID())
        let region = try #require(overlay.region)
        suite.defaults.removeObject(forKey: "RegionFrame.state.v1")
        var calls = 0
        overlay.regionDidChange = { _ in calls += 1 }
        let numbers = overlay.windowNumbers

        change.apply(to: overlay.panels[index])

        for (panel, edge) in zip(overlay.panels, BorderEdge.allCases) {
            #expect(panel.frame == BorderLayout.strip(for: edge, in: region.rect))
        }
        #expect(overlay.region == region)
        #expect(calls == 0)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") == nil)
        #expect(overlay.windowNumbers == numbers)
        #expect(overlay.panels.allSatisfy { !$0.isVisible })
    }

    @Test func ownPlacementIsNotUndone() throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let overlay = FrameOverlay(defaults: suite.defaults)
        var calls = 0
        overlay.regionDidChange = { _ in calls += 1 }

        func framesFollowRegion() throws -> FrameRegion {
            let region = try #require(overlay.region)
            for (panel, edge) in zip(overlay.panels, BorderEdge.allCases) {
                #expect(panel.frame == BorderLayout.strip(for: edge, in: region.rect))
            }
            return region
        }

        overlay.apply(preset: .left, on: CGMainDisplayID())
        let left = try framesFollowRegion()
        #expect(calls == 1)

        // Bottom-right corner drag, inward, through the same path a real mouse uses.
        let delegate = try #require(overlay.panels[0].borderView.delegate)
        let corner = CGPoint(x: left.rect.maxX - 1, y: left.rect.minY + 1)
        suite.defaults.removeObject(forKey: "RegionFrame.state.v1")
        delegate.borderMouseDown(at: corner)
        delegate.borderMouseDragged(to: CGPoint(x: corner.x - 320, y: corner.y + 180))
        let dragged = try framesFollowRegion()
        #expect(dragged.rect != left.rect)
        #expect(calls == 2)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") == nil)

        delegate.borderMouseUp()
        #expect(try framesFollowRegion() == dragged)
        #expect(suite.defaults.data(forKey: "RegionFrame.state.v1") != nil)

        // Presets are maximal, so one applied after an inward drag always differs,
        // even where the left and right presets coincide (any 16:9 display).
        overlay.apply(preset: .right, on: CGMainDisplayID())
        let right = try framesFollowRegion()
        #expect(right != dragged)
        #expect(calls == 3)
    }
}

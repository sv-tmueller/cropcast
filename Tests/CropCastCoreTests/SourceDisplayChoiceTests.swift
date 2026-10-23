import CoreGraphics
import Testing
@testable import CropCastCore

@Suite("SourceDisplayChoice")
struct SourceDisplayChoiceTests {
    private func d(_ id: UInt32, _ key: String, _ width: Double) -> DisplayCandidate {
        DisplayCandidate(id: id, key: key, name: "Display \(key)", width: width)
    }

    @Test func chosenWinsWhenConnected() {
        let displays = [d(1, "A", 5120), d(2, "B", 1920)]
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [], chosenKey: "B") == 2)
    }

    @Test func missingChosenFallsBackToWidest() {
        let displays = [d(1, "A", 1920), d(2, "B", 5120)]
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [], chosenKey: "gone") == 2)
    }

    @Test func chosenWinsAgainOnceItIsBack() {
        let wide = d(2, "B", 5120)
        let small = d(1, "A", 1920)
        #expect(SourceDisplayChoice.pick(from: [wide], excluding: [], chosenKey: "A") == 2)
        #expect(SourceDisplayChoice.pick(from: [small, wide], excluding: [], chosenKey: "A") == 1)
    }

    @Test func noChosenPicksWidest() {
        let displays = [d(1, "A", 1920), d(2, "B", 5120), d(3, "C", 2560)]
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [], chosenKey: nil) == 2)
    }

    @Test func widthTieGoesToTheFirstListed() {
        let displays = [d(7, "A", 2560), d(3, "B", 2560)]
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [], chosenKey: nil) == 7)
    }

    @Test func neverPicksTheExcludedDisplayEvenWhenWidestAndChosen() {
        let displays = [d(9, "V", 9000), d(1, "A", 1920)]
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [9], chosenKey: "V") == 1)
    }

    @Test func skipsEveryExcludedDisplay() {
        // An earlier virtual display that NSScreen still lists, plus the current one.
        let displays = [d(8, "V1", 9000), d(9, "V2", 8000), d(1, "A", 1920)]
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [8, 9], chosenKey: nil) == 1)
        #expect(SourceDisplayChoice.pick(from: displays, excluding: [8], chosenKey: nil) == 9)
    }

    @Test func nothingLeftReturnsNil() {
        #expect(SourceDisplayChoice.pick(from: [d(9, "V", 2560)], excluding: [9], chosenKey: nil) == nil)
        #expect(SourceDisplayChoice.pick(from: [], excluding: [], chosenKey: nil) == nil)
    }
}

@Suite("ScreenCoordinates")
struct ScreenCoordinatesTests {
    @Test func primaryDisplayAtOriginKeepsItsSize() {
        let bounds = CGRect(x: 0, y: 0, width: 5120, height: 1440)
        #expect(ScreenCoordinates.appKitFrame(forDisplayBounds: bounds, primaryHeight: 1440)
            == CGRect(x: 0, y: 0, width: 5120, height: 1440))
    }

    @Test func displayBelowThePrimaryHasNegativeY() {
        // CG: y grows downwards, so (-2560, 1440) is below-left of a 1440-high primary.
        let bounds = CGRect(x: -2560, y: 1440, width: 2560, height: 1440)
        #expect(ScreenCoordinates.appKitFrame(forDisplayBounds: bounds, primaryHeight: 1440)
            == CGRect(x: -2560, y: -1440, width: 2560, height: 1440))
    }

    @Test func displayAboveThePrimaryHasPositiveY() {
        let bounds = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        #expect(ScreenCoordinates.appKitFrame(forDisplayBounds: bounds, primaryHeight: 1440)
            == CGRect(x: 0, y: 1440, width: 1920, height: 1080))
    }

    @Test func settledOnlyWhenTheScreenFrameMatchesTheBounds() {
        let bounds = CGRect(x: -2560, y: 1440, width: 2560, height: 1440)
        let expected = CGRect(x: -2560, y: -1440, width: 2560, height: 1440)
        #expect(ScreenCoordinates.isSettled(screenFrame: expected, displayBounds: bounds, primaryHeight: 1440))
        #expect(!ScreenCoordinates.isSettled(screenFrame: nil, displayBounds: bounds, primaryHeight: 1440))
        #expect(!ScreenCoordinates.isSettled(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            displayBounds: bounds, primaryHeight: 1440))
    }
}

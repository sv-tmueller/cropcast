import CoreGraphics
import Testing

@testable import RegionMirror

@Suite("RegionGeometry.captureSourceRect")
struct RegionGeometryTests {
    @Test("primary display: AppKit region maps to top-left local rect")
    func primaryDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let region = CGRect(x: 100, y: 169, width: 1600, height: 900)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display)
                == CGRect(x: 100, y: 100, width: 1600, height: 900))
    }

    @Test("ultrawide: center slot")
    func ultrawideCenter() {
        let display = CGRect(x: -1652, y: 1169, width: 5120, height: 1440)
        let region = CGRect(x: -372, y: 1169, width: 2560, height: 1440)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display)
                == CGRect(x: 1280, y: 0, width: 2560, height: 1440))
    }

    @Test("ultrawide: left slot starts at x 0")
    func ultrawideLeft() {
        let display = CGRect(x: -1652, y: 1169, width: 5120, height: 1440)
        let region = CGRect(x: -1652, y: 1169, width: 2560, height: 1440)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display)
                == CGRect(x: 0, y: 0, width: 2560, height: 1440))
    }

    @Test("display below-left of the origin")
    func displayBelowLeft() {
        let display = CGRect(x: -1920, y: -1080, width: 1920, height: 1080)
        let region = CGRect(x: -1910, y: -1060, width: 160, height: 90)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display)
                == CGRect(x: 10, y: 970, width: 160, height: 90))
    }

    @Test("region partly outside the display is clipped")
    func partlyOutsideIsClipped() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 500)
        // Sticks out 100 pt left and 50 pt above the display.
        let region = CGRect(x: -100, y: 250, width: 400, height: 300)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display)
                == CGRect(x: 0, y: 0, width: 300, height: 250))
    }

    @Test("region fully outside returns nil")
    func fullyOutsideIsNil() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let region = CGRect(x: 2000, y: 0, width: 100, height: 100)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display) == nil)
    }

    @Test("region that only touches the display edge returns nil")
    func edgeTouchIsNil() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let region = CGRect(x: 1000, y: 0, width: 100, height: 100)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: region, displayFrame: display) == nil)
    }

    @Test("empty region returns nil")
    func emptyRegionIsNil() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 500)
        #expect(
            RegionGeometry.captureSourceRect(forAppKitRegion: .zero, displayFrame: display) == nil)
    }
}

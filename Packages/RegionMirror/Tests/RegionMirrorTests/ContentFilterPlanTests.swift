import CoreGraphics
import Testing

@testable import RegionMirror

@Suite("ContentFilterPlan.make")
struct ContentFilterPlanTests {
    private let me: pid_t = 100
    private let other: pid_t = 200

    private func window(_ id: CGWindowID, pid: pid_t) -> ContentFilterPlan.Window {
        .init(windowID: id, processID: pid)
    }

    @Test("selfApp found, no extras: excludes the whole app with no exceptions")
    func pureSelf() {
        let plan = ContentFilterPlan.make(
            ownProcessID: me, selfAppFound: true,
            windows: [window(1, pid: me), window(2, pid: other)], extraWindowIDs: [])
        #expect(plan == .excludingApp(exceptingWindows: []))
    }

    @Test("selfApp found, foreign extra: still excludes the whole app, extra is an exception")
    func foreignExtraKeepsAppExclusion() {
        let plan = ContentFilterPlan.make(
            ownProcessID: me, selfAppFound: true,
            windows: [window(1, pid: me), window(2, pid: other)], extraWindowIDs: [2])
        #expect(plan == .excludingApp(exceptingWindows: [2]))
    }

    @Test("selfApp found: own windows never appear in exceptingWindows")
    func ownWindowsNeverExcepted() {
        let plan = ContentFilterPlan.make(
            ownProcessID: me, selfAppFound: true,
            windows: [window(1, pid: me), window(2, pid: other)], extraWindowIDs: [1, 2])
        #expect(plan == .excludingApp(exceptingWindows: [2]))
    }

    @Test("selfApp found: unknown extra ids are dropped")
    func unknownExtraDropped() {
        let plan = ContentFilterPlan.make(
            ownProcessID: me, selfAppFound: true,
            windows: [window(2, pid: other)], extraWindowIDs: [99])
        #expect(plan == .excludingApp(exceptingWindows: []))
    }

    @Test("selfApp missing: falls back to own windows plus foreign extras")
    func selfAppMissing() {
        let plan = ContentFilterPlan.make(
            ownProcessID: me, selfAppFound: false,
            windows: [window(1, pid: me), window(2, pid: other), window(3, pid: other)],
            extraWindowIDs: [2])
        #expect(plan == .excludingWindows([1, 2]))
    }

    @Test("selfApp missing, no extras: excludes own windows only")
    func selfAppMissingNoExtras() {
        let plan = ContentFilterPlan.make(
            ownProcessID: me, selfAppFound: false,
            windows: [window(1, pid: me), window(2, pid: other)], extraWindowIDs: [])
        #expect(plan == .excludingWindows([1]))
    }
}

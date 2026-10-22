import CoreGraphics
import Foundation
import Testing
@testable import RegionFrame

/// A throwaway defaults suite, unique per test. Never `.standard`, never the demo's suite.
struct TestSuite {
    let name = "test.regionframe.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: name)!
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: name)
    }
}

@Suite struct FrameStoreTests {
    @Test func emptyDefaultsLoadAnEmptyState() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let state = FrameStore(defaults: suite.defaults).load()
        #expect(state.lastDisplayKey == nil)
        #expect(state.frames.isEmpty)
    }

    @Test func savedStateReloadsWithANewInstanceOnTheSameSuite() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        var state = FrameState()
        state.record(localRect: CGRect(x: 100, y: 50, width: 1280, height: 720), forDisplay: "A")
        FrameStore(defaults: suite.defaults).save(state)

        let reloaded = FrameStore(defaults: suite.defaults).load()
        #expect(reloaded.localRect(forDisplay: "A") == CGRect(x: 100, y: 50, width: 1280, height: 720))
    }

    @Test func twoDisplaysDoNotInterfere() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        let store = FrameStore(defaults: suite.defaults)
        var state = store.load()
        state.record(localRect: CGRect(x: 1, y: 2, width: 640, height: 360), forDisplay: "A")
        store.save(state)
        state = store.load()
        state.record(localRect: CGRect(x: 3, y: 4, width: 1280, height: 720), forDisplay: "B")
        store.save(state)

        let reloaded = FrameStore(defaults: suite.defaults).load()
        #expect(reloaded.localRect(forDisplay: "A") == CGRect(x: 1, y: 2, width: 640, height: 360))
        #expect(reloaded.localRect(forDisplay: "B") == CGRect(x: 3, y: 4, width: 1280, height: 720))
        #expect(reloaded.localRect(forDisplay: "C") == nil)
    }

    @Test func lastDisplayKeySurvivesAndFollowsTheLatestRecord() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        var state = FrameState()
        state.record(localRect: CGRect(x: 0, y: 0, width: 640, height: 360), forDisplay: "A")
        state.record(localRect: CGRect(x: 0, y: 0, width: 640, height: 360), forDisplay: "B")
        FrameStore(defaults: suite.defaults).save(state)
        #expect(FrameStore(defaults: suite.defaults).load().lastDisplayKey == "B")
    }

    @Test func recordingAgainOverwritesThatDisplaysRect() {
        var state = FrameState()
        state.record(localRect: CGRect(x: 0, y: 0, width: 640, height: 360), forDisplay: "A")
        state.record(localRect: CGRect(x: 5, y: 6, width: 800, height: 450), forDisplay: "A")
        #expect(state.localRect(forDisplay: "A") == CGRect(x: 5, y: 6, width: 800, height: 450))
        #expect(state.frames.count == 1)
    }

    @Test func corruptDataLoadsAsEmpty() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        suite.defaults.set(Data("not json at all".utf8), forKey: FrameStore.key)
        let state = FrameStore(defaults: suite.defaults).load()
        #expect(state.lastDisplayKey == nil)
        #expect(state.frames.isEmpty)
    }

    @Test func wrongTypeUnderTheKeyLoadsAsEmpty() {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        suite.defaults.set("a string, not data", forKey: FrameStore.key)
        #expect(FrameStore(defaults: suite.defaults).load().frames.isEmpty)
    }

    @Test func unknownVersionLoadsAsEmpty() throws {
        let suite = TestSuite()
        defer { suite.cleanUp() }
        var state = FrameState()
        state.record(localRect: CGRect(x: 0, y: 0, width: 640, height: 360), forDisplay: "A")
        state.version = 99
        suite.defaults.set(try JSONEncoder().encode(state), forKey: FrameStore.key)
        #expect(FrameStore(defaults: suite.defaults).load().frames.isEmpty)
    }

    @Test func storesUnderTheVersionedKey() {
        #expect(FrameStore.key == "RegionFrame.state.v1")
    }
}

import Foundation
import Testing
@testable import CropCastCore

@Suite("CaptureFrameRateSetting")
struct CaptureFrameRateSettingTests {
    @Test func unsetMeans30() {
        #expect(CaptureFrameRateSetting.framesPerSecond(stored: nil) == 30)
    }

    @Test(arguments: [30, 60])
    func eachAllowedValueIsKept(value: Int) {
        #expect(CaptureFrameRateSetting.framesPerSecond(stored: value) == value)
    }

    @Test(arguments: [0, -30, 24, 45, 120])
    func aValueThatIsNotAllowedMeansTheDefault(value: Int) {
        #expect(CaptureFrameRateSetting.framesPerSecond(stored: value) == 30)
    }

    @Test func aStoredValueOfTheWrongTypeMeansTheDefault() {
        #expect(CaptureFrameRateSetting.framesPerSecond(stored: "60") == 30)
        #expect(CaptureFrameRateSetting.framesPerSecond(stored: true) == 30)
        #expect(CaptureFrameRateSetting.framesPerSecond(stored: [60]) == 30)
    }

    @Test func allowedValuesAre30And60WithDefault30() {
        #expect(CaptureFrameRateSetting.allowedValues == [30, 60])
        #expect(CaptureFrameRateSetting.defaultValue == 30)
    }

    @Test func keyIsStableSoARenameCannotDropTheSetting() {
        #expect(CaptureFrameRateSetting.key == "CropCast.captureFramesPerSecond")
    }

    @Test func aWrongTypeInDefaultsReadsAsTheDefault() throws {
        let suite = "CropCastTests.CaptureFrameRateSetting.wrong.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("60", forKey: CaptureFrameRateSetting.key)
        #expect(CaptureFrameRateSetting.load(from: defaults) == 30)
    }

    @Test func sixtySurvivesANewDefaultsInstance() throws {
        let suite = "CropCastTests.CaptureFrameRateSetting.\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: suite))
        defer { first.removePersistentDomain(forName: suite) }
        #expect(CaptureFrameRateSetting.load(from: first) == 30)
        CaptureFrameRateSetting.save(60, to: first)

        let second = try #require(UserDefaults(suiteName: suite))
        #expect(CaptureFrameRateSetting.load(from: second) == 60)
    }

    @Test func savingAValueThatIsNotAllowedKeepsThePreviousChoice() throws {
        let suite = "CropCastTests.CaptureFrameRateSetting.bad.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        CaptureFrameRateSetting.save(60, to: defaults)
        CaptureFrameRateSetting.save(45, to: defaults)
        #expect(CaptureFrameRateSetting.load(from: defaults) == 60)
    }
}

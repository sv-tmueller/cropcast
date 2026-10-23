import Testing
@testable import CropCastCore

@Suite("ScreenCaptureReset")
struct ScreenCaptureResetTests {
    private let id = "com.github.sv-tmueller.cropcast"

    @Test func validIDGivesExactlyTheThreeArgumentReset() throws {
        #expect(try ScreenCaptureReset.arguments(bundleID: id) == ["reset", "ScreenCapture", id])
    }

    @Test func executableIsTccutil() {
        #expect(ScreenCaptureReset.executablePath == "/usr/bin/tccutil")
    }

    @Test func nilIDIsMissing() {
        #expect(throws: ScreenCaptureReset.Failure.missingBundleID) {
            try ScreenCaptureReset.arguments(bundleID: nil)
        }
    }

    @Test(arguments: ["", "   ", "\n"])
    func blankIDIsMissing(_ blank: String) {
        #expect(throws: ScreenCaptureReset.Failure.missingBundleID) {
            try ScreenCaptureReset.arguments(bundleID: blank)
        }
    }

    @Test(arguments: ["-r", "--help", ".hidden", "com.x y", "com.x\n", "com/x", "com.x;ls", "cöm.x"])
    func malformedIDIsInvalid(_ bad: String) {
        #expect(throws: ScreenCaptureReset.Failure.invalidBundleID(bad)) {
            try ScreenCaptureReset.arguments(bundleID: bad)
        }
    }

    @Test func exitZeroIsSuccess() throws {
        try ScreenCaptureReset.check(
            exitStatus: 0, output: "Successfully reset ScreenCapture", bundleID: id)
    }

    @Test func nonzeroExitNamesStatusOutputAndFallback() {
        let failure = ScreenCaptureReset.Failure.exited(
            status: 1, output: "No such bundle identifier \"x\"", bundleID: id)
        #expect(throws: failure) {
            try ScreenCaptureReset.check(
                exitStatus: 1, output: "  No such bundle identifier \"x\"\n", bundleID: id)
        }
        let text = failure.errorDescription ?? ""
        #expect(text.contains("1"))
        #expect(text.contains("No such bundle identifier"))
        #expect(text.contains("tccutil reset ScreenCapture \(id)"))
    }

    @Test func launchFailureTextContainsTheErrorAndFallback() {
        let text = ScreenCaptureReset.Failure.launchFailed("no such file", bundleID: id)
            .errorDescription ?? ""
        #expect(text.contains("no such file"))
        #expect(text.contains("tccutil reset ScreenCapture \(id)"))
    }

    @Test func missingIDTextNamesTheCauseAndGenericFallback() {
        let text = ScreenCaptureReset.Failure.missingBundleID.errorDescription ?? ""
        #expect(text.contains("bundle identifier"))
        #expect(text.contains("tccutil reset ScreenCapture"))
    }
}

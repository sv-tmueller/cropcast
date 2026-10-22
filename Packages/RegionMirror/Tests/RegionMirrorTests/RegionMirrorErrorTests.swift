import Foundation
import ScreenCaptureKit
import Testing

@testable import RegionMirror

@Suite("RegionMirrorError.init(captureError:)")
struct RegionMirrorErrorTests {
    @Test("SCStream userDeclined (-3801) maps to permissionDenied")
    func userDeclined() {
        let error = NSError(domain: SCStreamErrorDomain, code: -3801)
        #expect(RegionMirrorError(captureError: error) == .permissionDenied)
    }

    @Test("other SCStream errors map to captureFailed with code and description")
    func otherStreamError() {
        let error = NSError(
            domain: SCStreamErrorDomain, code: -3815,
            userInfo: [NSLocalizedDescriptionKey: "Failed to find any displays or windows to capture"])
        #expect(
            RegionMirrorError(captureError: error)
                == .captureFailed(
                    code: -3815, description: "Failed to find any displays or windows to capture"))
    }

    @Test("-3801 in a foreign domain is not treated as a permission error")
    func foreignDomain() {
        let error = NSError(domain: "SomethingElse", code: -3801)
        guard case .captureFailed(let code, _) = RegionMirrorError(captureError: error) else {
            Issue.record("expected captureFailed")
            return
        }
        #expect(code == -3801)
    }

    @Test("an existing RegionMirrorError passes through unchanged")
    func passThrough() {
        #expect(RegionMirrorError(captureError: RegionMirrorError.notRunning) == .notRunning)
    }

    @Test("every case has a non-empty description")
    func descriptions() {
        let all: [RegionMirrorError] = [
            .permissionDenied, .displayNotFound(7), .regionOutsideDisplay, .notRunning,
            .captureFailed(code: 1, description: "x"),
        ]
        for error in all {
            #expect(!error.localizedDescription.isEmpty)
            #expect(!"\(error)".isEmpty)
        }
    }
}

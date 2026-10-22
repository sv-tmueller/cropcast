import Foundation
import Testing

import CVirtualDisplayShim

@testable import VirtualDisplay

@MainActor
struct ErrorMappingTests {
    private static func shimError(_ code: CVDShimError.Code, _ message: String) -> NSError {
        NSError(
            domain: CVDShimErrorDomain, code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message])
    }

    @Test func apiUnavailableKeepsItsMessage() {
        let mapped = VirtualDisplay.mapShimError(Self.shimError(.apiUnavailable, "gone"))
        #expect(mapped == .apiUnavailable("gone"))
    }

    @Test func creationFailedKeepsItsMessage() {
        let mapped = VirtualDisplay.mapShimError(Self.shimError(.creationFailed, "refused"))
        #expect(mapped == .creationFailed("refused"))
    }

    @Test func settingsRejectedMapsToSettingsRejected() {
        let mapped = VirtualDisplay.mapShimError(Self.shimError(.settingsRejected, "no"))
        #expect(mapped == .settingsRejected)
    }

    @Test func unknownCodeInShimDomainMapsToCreationFailed() {
        let error = NSError(
            domain: CVDShimErrorDomain, code: 999,
            userInfo: [NSLocalizedDescriptionKey: "new code"])
        #expect(VirtualDisplay.mapShimError(error) == .creationFailed("new code"))
    }

    @Test func foreignDomainMapsToCreationFailed() {
        // Code 3 is .settingsRejected in the shim domain; a foreign domain
        // must not be mistaken for it.
        let error = NSError(
            domain: NSCocoaErrorDomain, code: 3,
            userInfo: [NSLocalizedDescriptionKey: "foreign"])
        #expect(VirtualDisplay.mapShimError(error) == .creationFailed("foreign"))
    }
}

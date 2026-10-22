import CoreGraphics
import Foundation
import Testing

import VirtualDisplay

struct ErrorMessageTests {
    private static let all: [VirtualDisplayError] = [
        .apiUnavailable("gone"),
        .creationFailed("refused"),
        .settingsRejected,
        .didNotComeOnline,
        .placementFailed(CGError(rawValue: 1001)!),
    ]

    private static func description(_ error: VirtualDisplayError) -> String? {
        (error as? LocalizedError)?.errorDescription
    }

    @Test(arguments: all)
    func everyCaseHasANonEmptyDescription(error: VirtualDisplayError) {
        #expect(Self.description(error)?.isEmpty == false, "\(error)")
    }

    @Test func detailsAreKept() {
        #expect(Self.description(.apiUnavailable("gone"))?.contains("gone") == true)
        #expect(Self.description(.creationFailed("refused"))?.contains("refused") == true)
        #expect(Self.description(.placementFailed(CGError(rawValue: 1001)!))?.contains("1001") == true)
        #expect(Self.description(.didNotComeOnline)?.contains("NSApplication.run()") == true)
    }

    @Test(arguments: all)
    func bridgedNSErrorUsesTheSameDescription(error: VirtualDisplayError) {
        let description = Self.description(error)
        #expect(description != nil)
        #expect((error as NSError).localizedDescription == description)
    }
}

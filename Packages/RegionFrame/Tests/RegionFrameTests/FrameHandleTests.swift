import Testing
@testable import RegionFrame

@Suite struct FrameHandleTests {
    @Test func hasEightHandles() {
        #expect(FrameHandle.allCases.count == 8)
    }
}

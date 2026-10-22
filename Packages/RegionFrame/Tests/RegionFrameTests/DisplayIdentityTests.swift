import CoreGraphics
import Testing
@testable import RegionFrame

@Suite struct DisplayIdentityTests {
    @Test func fallbackKeyJoinsVendorModelAndSerial() {
        #expect(DisplayIdentity.fallbackKey(vendor: 1552, model: 40960, serial: 7) == "cg-1552-40960-7")
    }

    @Test func mainDisplayKeyIsStableAndNotEmpty() {
        let id = CGMainDisplayID()
        let key = DisplayIdentity.key(for: id)
        #expect(!key.isEmpty)
        #expect(key == DisplayIdentity.key(for: id))
    }
}

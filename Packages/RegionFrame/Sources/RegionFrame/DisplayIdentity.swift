import AppKit

/// Maps between `CGDirectDisplayID`, `NSScreen` and a persistent display key.
/// (RegionMirror has a similar helper; modules never import each other, so it is duplicated.)
enum DisplayIdentity {
    /// The display id behind an `NSScreen`, read from `deviceDescription["NSScreenNumber"]`.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The connected screen with this display id.
    @MainActor
    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    /// A key that identifies the physical display across launches and reconnects:
    /// the display UUID, or vendor/model/serial when the system gives no UUID.
    static func key(for id: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return fallbackKey(vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
    }

    static func fallbackKey(vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        "cg-\(vendor)-\(model)-\(serial)"
    }
}

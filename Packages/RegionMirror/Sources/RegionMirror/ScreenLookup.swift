import AppKit
import CoreGraphics

/// Finds the `NSScreen` for a display id.
///
/// Uses `deviceDescription["NSScreenNumber"]` because `NSScreen.cgDirectDisplayID`
/// only exists on macOS 26 and the package targets macOS 14.
enum ScreenLookup {
    @MainActor
    static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            return (number as? NSNumber)?.uint32Value == displayID
        }
    }
}

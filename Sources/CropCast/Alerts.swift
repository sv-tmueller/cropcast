import AppKit
import CoreGraphics
import CropCastCore

/// Where the session shows its alerts. The self-test substitutes a logging
/// presenter so it never opens a modal alert or asks for permission.
@MainActor
protocol AlertPresenting: AnyObject {
    func presentPermissionNeeded()
    func presentStartFailure(step: StartStepID, error: any Error)
}

/// The real alerts, as modal `NSAlert`s.
@MainActor
final class AlertPresenter: AlertPresenting {
    private static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    func presentPermissionNeeded() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "CropCast needs Screen Recording permission"
        alert.informativeText = """
            CropCast copies a region of your screen onto a virtual display so you can share it. \
            macOS only allows that after you grant Screen Recording access.

            Open System Settings, switch CropCast on under Privacy & Security > Screen & System \
            Audio Recording, then reopen CropCast.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = CGRequestScreenCaptureAccess()
        if let url = Self.settingsURL { NSWorkspace.shared.open(url) }
    }

    func presentStartFailure(step: StartStepID, error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sharing did not start"
        alert.informativeText = StartFailureMessage.make(step: step, error: error)
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}

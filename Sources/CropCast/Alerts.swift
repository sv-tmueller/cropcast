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

            If System Settings already shows CropCast switched on (for example after a rebuild), \
            that grant is stale. Choose Reset & Grant Again to clear it and grant it fresh, then \
            reopen CropCast.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Reset & Grant Again")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            requestAccessAndOpenSettings()
        case .alertSecondButtonReturn:
            resetAndGrantAgain()
        default:
            break
        }
    }

    private func requestAccessAndOpenSettings() {
        _ = CGRequestScreenCaptureAccess()
        if let url = Self.settingsURL { NSWorkspace.shared.open(url) }
    }

    /// Clears the stale grant, then asks again. Any failure is shown and stops
    /// here: no access request, no Settings pane.
    private func resetAndGrantAgain() {
        let bundleID = Bundle.main.bundleIdentifier
        Task { @MainActor in
            do {
                let arguments = try ScreenCaptureReset.arguments(bundleID: bundleID)
                try await Self.runTccutil(arguments: arguments, bundleID: bundleID)
                requestAccessAndOpenSettings()
            } catch {
                presentResetFailure(error)
            }
        }
    }

    /// Runs tccutil off the main actor so the main run loop is not spun while waiting.
    private nonisolated static func runTccutil(arguments: [String], bundleID: String?) async throws {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ScreenCaptureReset.executablePath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                throw ScreenCaptureReset.Failure.launchFailed(
                    error.localizedDescription, bundleID: bundleID)
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            try ScreenCaptureReset.check(
                exitStatus: process.terminationStatus,
                output: String(decoding: data, as: UTF8.self),
                bundleID: bundleID)
        }.value
    }

    private func presentResetFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not reset Screen Recording permission"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
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

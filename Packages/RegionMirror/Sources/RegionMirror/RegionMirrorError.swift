import CoreGraphics
import Foundation
import ScreenCaptureKit

/// The only error type thrown by the RegionMirror module.
public enum RegionMirrorError: Error, Equatable, Sendable {
    /// Screen Recording permission is missing or was declined.
    case permissionDenied
    /// No display with this id is currently connected or shareable.
    case displayNotFound(CGDirectDisplayID)
    /// The requested region does not overlap the source display.
    case regionOutsideDisplay
    /// The operation needs a running capture, or a start was cancelled by `stop()`.
    case notRunning
    /// ``RegionCapture/start(region:renderer:)`` was called while a capture is
    /// already starting or running.
    case alreadyRunning
    /// ScreenCaptureKit (or another system call) failed.
    case captureFailed(code: Int, description: String)

    /// Maps an error from ScreenCaptureKit onto this module's error type.
    public init(captureError error: any Error) {
        if let mirrorError = error as? RegionMirrorError {
            self = mirrorError
            return
        }
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain,
            nsError.code == SCStreamError.Code.userDeclined.rawValue
        {
            self = .permissionDenied
            return
        }
        self = .captureFailed(code: nsError.code, description: nsError.localizedDescription)
    }
}

extension RegionMirrorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is not granted."
        case .displayNotFound(let id):
            return "Display \(id) was not found."
        case .regionOutsideDisplay:
            return "The region does not overlap the source display."
        case .notRunning:
            return "Capture is not running."
        case .alreadyRunning:
            return "Capture is already starting or running."
        case .captureFailed(let code, let description):
            return "Capture failed (\(code)): \(description)"
        }
    }
}

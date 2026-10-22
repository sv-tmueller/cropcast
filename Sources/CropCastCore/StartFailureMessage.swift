import Foundation

/// Text of the alert shown when a start step fails.
public enum StartFailureMessage {
    /// Uses the error's `LocalizedError` description if it has one, else
    /// `String(describing:)`.
    public static func make(step: StartStepID, error: any Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return "CropCast could not \(step.title).\n\n\(detail)"
    }
}

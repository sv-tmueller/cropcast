import Foundation

/// Text of the alert shown when a start step fails.
public enum StartFailureMessage {
    /// Module error enums carry no `LocalizedError` of their own on purpose;
    /// whatever description exists is used, else the error is dumped.
    public static func make(step: StartStepID, error: any Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return "CropCast could not \(step.title).\n\n\(detail)"
    }
}

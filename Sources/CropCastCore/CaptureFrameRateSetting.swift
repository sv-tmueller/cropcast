import Foundation

/// The "Frame rate" setting: how many frames per second a session captures.
/// 30 by default; a change applies from the next Start Sharing.
public enum CaptureFrameRateSetting {
    /// Literal on purpose: a rename would silently drop the user's choice.
    public static let key = "CropCast.captureFramesPerSecond"

    public static let allowedValues = [30, 60]
    public static let defaultValue = 30

    /// Nothing stored, a value that is not allowed, or a value of the wrong
    /// type means the default.
    public static func framesPerSecond(stored: Any?) -> Int {
        guard let value = stored as? Int, allowedValues.contains(value) else { return defaultValue }
        return value
    }

    public static func load(from defaults: UserDefaults) -> Int {
        framesPerSecond(stored: defaults.object(forKey: key))
    }

    /// A value that is not allowed is ignored, so the stored choice stays valid.
    public static func save(_ framesPerSecond: Int, to defaults: UserDefaults) {
        guard allowedValues.contains(framesPerSecond) else { return }
        defaults.set(framesPerSecond, forKey: key)
    }
}

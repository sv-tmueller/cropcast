import Foundation

/// The "Lock frame" setting: while on, the frame cannot be grabbed with the
/// mouse. Off by default.
public enum LockFrameSetting {
    /// Literal on purpose: a rename would silently drop the user's choice.
    public static let key = "CropCast.lockFrame"

    /// Nothing stored yet means unlocked.
    public static func isLocked(stored: Bool?) -> Bool {
        stored ?? false
    }

    public static func load(from defaults: UserDefaults) -> Bool {
        isLocked(stored: defaults.object(forKey: key) as? Bool)
    }

    public static func save(_ isLocked: Bool, to defaults: UserDefaults) {
        defaults.set(isLocked, forKey: key)
    }
}

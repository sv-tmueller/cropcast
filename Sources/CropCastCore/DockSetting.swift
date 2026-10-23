import Foundation

/// Mirrors `NSApplication.ActivationPolicy` for the two modes CropCast uses;
/// the app glue maps it.
public enum ActivationMode: Sendable, Equatable {
    /// Dock icon and app menu.
    case regular
    /// Menu bar icon only.
    case accessory
}

/// The "Show in Dock" setting. On by default.
public enum DockSetting {
    /// Literal on purpose: a rename would silently drop the user's choice.
    public static let key = "CropCast.showInDock"

    /// Nothing stored yet means shown.
    public static func isShown(stored: Bool?) -> Bool {
        stored ?? true
    }

    public static func activationMode(isShown: Bool) -> ActivationMode {
        isShown ? .regular : .accessory
    }

    public static func load(from defaults: UserDefaults) -> Bool {
        isShown(stored: defaults.object(forKey: key) as? Bool)
    }

    public static func save(_ isShown: Bool, to defaults: UserDefaults) {
        defaults.set(isShown, forKey: key)
    }
}

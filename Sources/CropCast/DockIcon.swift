import AppKit
import CropCastCore

/// Applies the "Show in Dock" setting and owns the minimal app menu. The app
/// menu only shows while CropCast has a Dock icon and is active, but it is
/// installed in both modes so Command-comma and Command-Q work either way.
@MainActor
final class DockIcon: NSObject {
    var onOpenSettings: (() -> Void)?

    /// Maps the core activation mode onto the AppKit policy.
    static func apply(isShown: Bool) {
        switch DockSetting.activationMode(isShown: isShown) {
        case .regular: NSApp.setActivationPolicy(.regular)
        case .accessory: NSApp.setActivationPolicy(.accessory)
        }
    }

    /// One app menu: Settings… (Command-comma), a separator, Quit CropCast
    /// (Command-Q). Quit goes through `NSApp.terminate(_:)` so the delegate's
    /// teardown in `applicationShouldTerminate` still runs.
    func installMainMenu() {
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings),
            keyEquivalent: MenuAction.openSettings.keyEquivalent)
        settings.target = self
        let quit = NSMenuItem(
            title: "Quit CropCast", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: MenuAction.quit.keyEquivalent)
        quit.target = NSApp

        let appMenu = NSMenu()
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(quit)

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}

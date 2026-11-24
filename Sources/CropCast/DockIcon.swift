import AppKit
import CropCastCore

/// Applies the "Show in Dock" setting and owns the minimal main menu. The menu
/// only shows while CropCast has a Dock icon and is active, but it is
/// installed in both modes so Command-comma, Command-W and Command-Q work
/// either way.
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

    /// An app menu (Settings… on Command-comma, a separator, Quit CropCast on
    /// Command-Q) and a File menu (Close Window on Command-W). Quit goes through `NSApp.terminate(_:)` so the delegate's
    /// teardown in `applicationShouldTerminate` still runs.
    func installMainMenu() {
        NSApp.mainMenu = makeMainMenu(quitTarget: NSApp)
    }

    /// Builds the main menu without installing it, so a test can inspect it.
    func makeMainMenu(quitTarget: AnyObject?) -> NSMenu {
        let settings = NSMenuItem(
            title: "Settings…", action: #selector(openSettings),
            keyEquivalent: MenuAction.openSettings.keyEquivalent)
        settings.target = self
        let quit = NSMenuItem(
            title: "Quit CropCast", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: MenuAction.quit.keyEquivalent)
        quit.target = quitTarget

        let appMenu = NSMenu()
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(quit)

        // No target: the action travels the responder chain to the key window.
        // AppKit disables the item when no closable window is key.
        let close = NSMenuItem(
            title: "Close Window", action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w")
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(close)

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        mainMenu.addItem(fileItem)
        return mainMenu
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }
}

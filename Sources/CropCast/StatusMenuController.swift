import AppKit
import CropCastCore

/// Owns the `NSStatusItem` and renders the menu. The menu is rebuilt from
/// `SharingController.menuEntries()` every time it opens, so labels are always current.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    let sharing: SharingController
    let statusItem: NSStatusItem
    private let menu = NSMenu()
    /// Set by the app delegate once the Settings window exists.
    var onOpenSettings: (() -> Void)?

    init(sharing: SharingController) {
        self.sharing = sharing
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "rectangle.dashed", accessibilityDescription: "CropCast")
            image?.isTemplate = true
            button.image = image
        }
        // Submenu items get their enabled state from the entries, not from AppKit.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Single entry point for menu clicks and the hotkey.
    func apply(_ action: MenuAction) {
        if action == .quit {
            NSApp.terminate(nil)
            return
        }
        if action == .openSettings {
            onOpenSettings?()
            return
        }
        sharing.apply(action)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in sharing.menuEntries() {
            menu.addItem(makeItem(entry))
        }
    }

    private func makeItem(_ entry: MenuEntry) -> NSMenuItem {
        switch entry {
        case .separator:
            return .separator()
        case let .item(title, action):
            let item = NSMenuItem(
                title: title, action: #selector(menuItemClicked(_:)),
                keyEquivalent: action.keyEquivalent)
            item.target = self
            item.representedObject = action
            return item
        case let .checkable(title, action, isChecked):
            let item = NSMenuItem(
                title: title, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action
            item.state = isChecked ? .on : .off
            return item
        case let .submenu(title, entries, isEnabled):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = isEnabled
            let submenu = NSMenu(title: title)
            for child in entries {
                submenu.addItem(makeItem(child))
            }
            item.submenu = submenu
            return item
        }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuAction else { return }
        apply(action)
    }
}

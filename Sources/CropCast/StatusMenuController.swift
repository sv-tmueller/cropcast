import AppKit
import CropCastCore

/// Owns the `NSStatusItem` and the app state. The menu is rebuilt from
/// `AppState.menuEntries()` every time it opens, so labels are always current.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private(set) var state = AppState()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "rectangle.dashed", accessibilityDescription: "CropCast")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    /// Single entry point for menu clicks and the hotkey.
    func apply(_ action: MenuAction) {
        if action == .quit {
            NSApp.terminate(nil)
            return
        }
        state.apply(action)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in state.menuEntries() {
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
                keyEquivalent: action == .quit ? "q" : "")
            item.target = self
            item.representedObject = ActionBox(action)
            return item
        case let .submenu(title, entries):
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            for child in entries {
                submenu.addItem(makeItem(child))
            }
            item.submenu = submenu
            return item
        }
    }

    @objc private func menuItemClicked(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        apply(box.action)
    }
}

private final class ActionBox: NSObject {
    let action: MenuAction
    init(_ action: MenuAction) { self.action = action }
}

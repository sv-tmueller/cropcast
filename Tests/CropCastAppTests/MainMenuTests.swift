import AppKit
import Testing
@testable import CropCast

@MainActor
@Suite("Main menu")
struct MainMenuTests {
    private func fileMenu() throws -> NSMenu {
        let menu = DockIcon().makeMainMenu(quitTarget: NSObject())
        let item = try #require(menu.items.first { $0.submenu?.title == "File" })
        return try #require(item.submenu)
    }

    @Test func fileMenuHoldsCloseWindowOnCommandW() throws {
        let items = try fileMenu().items
        #expect(items.count == 1)
        let close = try #require(items.first)
        #expect(close.title == "Close Window")
        #expect(close.keyEquivalent == "w")
        #expect(close.keyEquivalentModifierMask == .command)
    }

    @Test func closeWindowGoesToTheKeyWindowThroughTheResponderChain() throws {
        let close = try #require(try fileMenu().items.first)
        #expect(close.action == #selector(NSWindow.performClose(_:)))
        #expect(close.target == nil)
    }

    @Test func settingsAndQuitStayInTheAppMenu() throws {
        let menu = DockIcon().makeMainMenu(quitTarget: NSObject())
        let appMenu = try #require(menu.items.first?.submenu)
        #expect(appMenu.items.map(\.title) == ["Settings…", "", "Quit CropCast"])
        #expect(appMenu.items.map(\.keyEquivalent) == [",", "", "q"])
    }
}

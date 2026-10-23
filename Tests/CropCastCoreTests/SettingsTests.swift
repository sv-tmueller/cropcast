import Foundation
import Testing
@testable import CropCastCore

@Suite("DockSetting")
struct DockSettingTests {
    @Test func unsetMeansShown() {
        #expect(DockSetting.isShown(stored: nil) == true)
    }

    @Test func storedValueWins() {
        #expect(DockSetting.isShown(stored: true) == true)
        #expect(DockSetting.isShown(stored: false) == false)
    }

    @Test(arguments: [(true, ActivationMode.regular), (false, ActivationMode.accessory)])
    func shownMapsToActivationMode(isShown: Bool, expected: ActivationMode) {
        #expect(DockSetting.activationMode(isShown: isShown) == expected)
    }

    @Test func keyIsStableSoARenameCannotDropTheSetting() {
        #expect(DockSetting.key == "CropCast.showInDock")
    }

    @Test func storedFalseSurvivesANewDefaultsInstance() throws {
        let suite = "CropCastTests.DockSetting.\(UUID().uuidString)"
        let first = try #require(UserDefaults(suiteName: suite))
        defer { first.removePersistentDomain(forName: suite) }
        #expect(DockSetting.load(from: first) == true)
        DockSetting.save(false, to: first)

        let second = try #require(UserDefaults(suiteName: suite))
        #expect(DockSetting.load(from: second) == false)
    }
}

@Suite("LoginItemRow")
struct LoginItemRowTests {
    @Test func enabledIsOnWithoutNote() {
        let row = LoginItemRow.make(status: .enabled, error: nil)
        #expect(row == LoginItemRow(isOn: true, isEnabled: true, note: nil, showsOpenLoginItems: false))
    }

    @Test func notRegisteredIsOffWithoutNote() {
        let row = LoginItemRow.make(status: .notRegistered, error: nil)
        #expect(row == LoginItemRow(isOn: false, isEnabled: true, note: nil, showsOpenLoginItems: false))
    }

    @Test func requiresApprovalIsOffWithNoteAndButton() {
        let row = LoginItemRow.make(status: .requiresApproval, error: nil)
        #expect(row.isOn == false)
        #expect(row.isEnabled == true)
        #expect(row.note?.contains("Login Items") == true)
        #expect(row.showsOpenLoginItems == true)
    }

    @Test func notFoundDisablesTheSwitchAndPointsAtTheInstalledApp() {
        let row = LoginItemRow.make(status: .notFound, error: nil)
        #expect(row.isOn == false)
        #expect(row.isEnabled == false)
        #expect(row.note?.contains("CropCast.app") == true)
        #expect(row.showsOpenLoginItems == false)
    }

    @Test(arguments: [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound])
    func anErrorOverridesTheNote(status: LoginItemStatus) {
        let row = LoginItemRow.make(status: status, error: "boom")
        #expect(row.note == "boom")
        #expect(row.isOn == (status == .enabled))
    }
}

@Suite("LoginItemCommand")
struct LoginItemCommandTests {
    @Test(arguments: [
        (true, LoginItemStatus.notRegistered, LoginItemCommand.register),
        (false, .enabled, .unregister),
        (true, .enabled, .none),
        (false, .notRegistered, .none),
        (true, .requiresApproval, .openLoginItems),
        (false, .requiresApproval, .unregister),
        (true, .notFound, .none),
        (false, .notFound, .none),
    ])
    func commandForSwitchAndStatus(wantOn: Bool, status: LoginItemStatus, expected: LoginItemCommand) {
        #expect(LoginItemCommand.for(wantOn: wantOn, status: status) == expected)
    }
}

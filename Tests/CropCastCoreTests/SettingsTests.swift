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
        let row = LoginItemRow.make(status: .enabled, isAppBundle: true, error: nil)
        #expect(row == LoginItemRow(isOn: true, isEnabled: true, note: nil, showsOpenLoginItems: false))
    }

    @Test func notRegisteredIsOffWithoutNote() {
        let row = LoginItemRow.make(status: .notRegistered, isAppBundle: true, error: nil)
        #expect(row == LoginItemRow(isOn: false, isEnabled: true, note: nil, showsOpenLoginItems: false))
    }

    @Test func requiresApprovalIsOffWithNoteAndButton() {
        let row = LoginItemRow.make(status: .requiresApproval, isAppBundle: true, error: nil)
        #expect(row.isOn == false)
        #expect(row.isEnabled == true)
        #expect(row.note?.contains("Login Items") == true)
        #expect(row.showsOpenLoginItems == true)
    }

    /// An installed app that was never registered reports `.notFound`
    /// ("record not found"), so the switch must stay usable: registering is
    /// the only way out of that status.
    @Test func notFoundInAnAppBundleIsAUsableOffSwitchWithoutNote() {
        let row = LoginItemRow.make(status: .notFound, isAppBundle: true, error: nil)
        #expect(row == LoginItemRow(isOn: false, isEnabled: true, note: nil, showsOpenLoginItems: false))
    }

    @Test func notFoundOutsideAnAppBundleDisablesTheSwitchAndPointsAtTheInstalledApp() {
        let row = LoginItemRow.make(status: .notFound, isAppBundle: false, error: nil)
        #expect(row.isOn == false)
        #expect(row.isEnabled == false)
        #expect(row.note?.contains("CropCast.app") == true)
        #expect(row.showsOpenLoginItems == false)
    }

    @Test(arguments: [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound])
    func anErrorOverridesTheNote(status: LoginItemStatus) {
        let row = LoginItemRow.make(status: status, isAppBundle: true, error: "boom")
        #expect(row.note == "boom")
        #expect(row.isOn == (status == .enabled))
    }

    @Test func anErrorOutsideAnAppBundleStillShows() {
        let row = LoginItemRow.make(status: .notFound, isAppBundle: false, error: "boom")
        #expect(row.note == "boom")
        #expect(row.isEnabled == false)
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
        (true, .notFound, .register),
        (false, .notFound, .none),
    ])
    func commandInAnAppBundle(wantOn: Bool, status: LoginItemStatus, expected: LoginItemCommand) {
        #expect(LoginItemCommand.for(wantOn: wantOn, status: status, isAppBundle: true) == expected)
    }

    @Test(arguments: [true, false])
    func notFoundOutsideAnAppBundleDoesNothing(wantOn: Bool) {
        #expect(LoginItemCommand.for(wantOn: wantOn, status: .notFound, isAppBundle: false) == .none)
    }
}

@Suite("LoginItemStatus")
struct LoginItemStatusTests {
    @Test(arguments: [
        (LoginItemStatus.enabled, "enabled"),
        (.notRegistered, "notRegistered"),
        (.requiresApproval, "requiresApproval"),
        (.notFound, "notFound"),
    ])
    func nameIsTheCaseName(status: LoginItemStatus, expected: String) {
        #expect(status.name == expected)
    }
}

@Suite("LoginItemNote")
struct LoginItemNoteTests {
    @Test func failureToTurnOnNamesTheDescriptionDomainAndCode() {
        let note = LoginItemNote.failure(
            wantOn: true, domain: "SMAppServiceErrorDomain", code: 1, description: "Operation not permitted")
        #expect(note.text
            == "Could not turn on Launch at login: Operation not permitted (SMAppServiceErrorDomain 1).")
    }

    @Test func failureToTurnOffSaysOff() {
        let note = LoginItemNote.failure(wantOn: false, domain: "D", code: 3, description: "nope")
        #expect(note.text == "Could not turn off Launch at login: nope (D 3).")
    }

    @Test(arguments: ["", "  \n "])
    func anEmptyDescriptionStillGivesDomainAndCode(description: String) {
        let note = LoginItemNote.failure(wantOn: true, domain: "D", code: 22, description: description)
        #expect(note.text == "Could not turn on Launch at login (D 22).")
    }

    @Test(arguments: [LoginItemStatus.notRegistered, .notFound])
    func registerThatLeavesNoRegistrationIsReported(status: LoginItemStatus) {
        let note = LoginItemNote.check(wantOn: true, status: status)
        #expect(note?.text
            == "macOS did not add CropCast to Login Items (status: \(status.name)). Details are in the log.")
    }

    @Test func unregisterThatLeavesItEnabledIsReported() {
        let note = LoginItemNote.check(wantOn: false, status: .enabled)
        #expect(note?.text
            == "macOS did not remove CropCast from Login Items (status: enabled). Details are in the log.")
    }

    @Test(arguments: [
        (true, LoginItemStatus.enabled),
        (true, .requiresApproval),
        (false, .notRegistered),
        (false, .notFound),
        (false, .requiresApproval),
    ])
    func aCallThatWorkedOrAwaitsApprovalHasNoCheckNote(wantOn: Bool, status: LoginItemStatus) {
        #expect(LoginItemNote.check(wantOn: wantOn, status: status) == nil)
    }

    @Test(arguments: [LoginItemStatus.notRegistered, .notFound, .requiresApproval])
    func aFailureNoteSurvivesRefreshesThatDoNotShowTheRequestedState(status: LoginItemStatus) {
        let note = LoginItemNote.failure(wantOn: true, domain: "D", code: 1, description: "x")
        #expect(note.isResolved(by: status) == false)
    }

    @Test func aFailureNoteIsResolvedOnceTheRequestedStateShows() {
        let on = LoginItemNote.failure(wantOn: true, domain: "D", code: 1, description: "x")
        #expect(on.isResolved(by: .enabled) == true)
        let off = LoginItemNote.failure(wantOn: false, domain: "D", code: 1, description: "x")
        #expect(off.isResolved(by: .notRegistered) == true)
        #expect(off.isResolved(by: .enabled) == false)
    }

    @Test func aPendingCheckReplacesTheCurrentNote() {
        let carried = LoginItemNote.failure(wantOn: true, domain: "D", code: 1, description: "x")
        let note = LoginItemNote.afterRead(current: carried, pendingWantOn: true, status: .notRegistered)
        #expect(note == LoginItemNote.check(wantOn: true, status: .notRegistered))
        #expect(note != carried)
    }

    @Test func aPendingCheckThatPassesClearsTheCurrentNote() {
        let carried = LoginItemNote.check(wantOn: true, status: .notRegistered)
        #expect(LoginItemNote.afterRead(current: carried, pendingWantOn: true, status: .enabled) == nil)
    }

    @Test func aPendingCheckCreatesANoteWhenThereWasNone() {
        let note = LoginItemNote.afterRead(current: nil, pendingWantOn: false, status: .enabled)
        #expect(note == LoginItemNote.check(wantOn: false, status: .enabled))
        #expect(note != nil)
    }

    @Test func withoutAPendingCheckACarriedNoteStaysUntilTheStatusResolvesIt() {
        let carried = LoginItemNote.failure(wantOn: true, domain: "D", code: 1, description: "x")
        #expect(LoginItemNote.afterRead(current: carried, pendingWantOn: nil, status: .notRegistered) == carried)
        #expect(LoginItemNote.afterRead(current: carried, pendingWantOn: nil, status: .requiresApproval) == carried)
    }

    @Test func withoutAPendingCheckACarriedNoteIsClearedOnceTheStatusResolvesIt() {
        let carried = LoginItemNote.failure(wantOn: true, domain: "D", code: 1, description: "x")
        #expect(LoginItemNote.afterRead(current: carried, pendingWantOn: nil, status: .enabled) == nil)
    }

    @Test(arguments: [LoginItemStatus.enabled, .notRegistered, .requiresApproval, .notFound])
    func withoutAPendingCheckOrANoteThereStaysNoNote(status: LoginItemStatus) {
        #expect(LoginItemNote.afterRead(current: nil, pendingWantOn: nil, status: status) == nil)
    }
}

import AppKit
import CropCastCore
import SwiftUI

/// State behind the Settings form. Decisions come from `CropCastCore`; this
/// only reads the system and applies results.
@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var showInDock: Bool
    @Published private(set) var loginRow: LoginItemRow
    /// Called after the Dock policy changed, so the window can re-front itself.
    var dockDidChange: (() -> Void)?

    private let defaults: UserDefaults
    private let loginItem: any LoginItemService
    /// Why the last flip failed, kept until a status read shows the requested state.
    private var loginNote: LoginItemNote?
    /// Set after a call that did not throw: the wanted state to check the next reads against.
    private var pendingCheck: Bool?
    /// Bumped on every flip, so a delayed re-read of an older flip does nothing.
    private var flipGeneration = 0

    init(defaults: UserDefaults, loginItem: any LoginItemService) {
        self.defaults = defaults
        self.loginItem = loginItem
        showInDock = DockSetting.load(from: defaults)
        loginRow = LoginItemRow.make(status: loginItem.status, isAppBundle: loginItem.isAppBundle, error: nil)
    }

    func refresh() {
        applyStatus(loginItem.status)
    }

    private func applyStatus(_ status: LoginItemStatus) {
        loginNote = LoginItemNote.afterRead(current: loginNote, pendingWantOn: pendingCheck, status: status)
        loginRow = LoginItemRow.make(
            status: status, isAppBundle: loginItem.isAppBundle, error: loginNote?.text)
    }

    func setShowInDock(_ isShown: Bool) {
        DockSetting.save(isShown, to: defaults)
        showInDock = isShown
        DockIcon.apply(isShown: isShown)
        dockDidChange?()
    }

    func setLaunchAtLogin(_ wantOn: Bool) {
        flipGeneration += 1
        let generation = flipGeneration
        loginNote = nil
        pendingCheck = nil
        do {
            switch LoginItemCommand.for(wantOn: wantOn, status: loginItem.status, isAppBundle: loginItem.isAppBundle) {
            case .register:
                try loginItem.register()
                pendingCheck = wantOn
            case .unregister:
                try loginItem.unregister()
                pendingCheck = wantOn
            case .openLoginItems: loginItem.openSystemSettings()
            case .none: break
            }
        } catch {
            let ns = error as NSError
            loginNote = LoginItemNote.failure(
                wantOn: wantOn, domain: ns.domain, code: ns.code, description: ns.localizedDescription)
        }
        refresh()
        // The system can lag behind the call, so read once more shortly after,
        // also after a call that threw: the change may still have taken effect.
        guard pendingCheck != nil || loginNote != nil else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.flipGeneration == generation else { return }
            self.refresh()
            // Later reads (window focus) only resolve the note; a change made
            // in System Settings must not read as a failed call.
            self.pendingCheck = nil
        }
    }

    func openLoginItems() {
        loginItem.openSystemSettings()
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Show in Dock",
                    isOn: Binding(get: { model.showInDock }, set: { model.setShowInDock($0) }))
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { model.loginRow.isOn }, set: { model.setLaunchAtLogin($0) })
                    )
                    .disabled(!model.loginRow.isEnabled)
                    if let note = model.loginRow.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if model.loginRow.showsOpenLoginItems {
                        Button("Open Login Items…") { model.openLoginItems() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}

/// Owns the single Settings window, created on first use.
@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?
    private var keyObserver: (any NSObjectProtocol)?

    init(defaults: UserDefaults = .standard, loginItem: any LoginItemService = LiveLoginItemService()) {
        model = SettingsModel(defaults: defaults, loginItem: loginItem)
        model.dockDidChange = { [weak self] in self?.refront() }
    }

    /// Opens the window, or brings the existing one to the front.
    func show() {
        model.refresh()
        let window = self.window ?? makeWindow()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "CropCast Settings"
        window.styleMask = [.titled, .closable]
        // A code-created window would be over-released on close under ARC.
        window.isReleasedWhenClosed = false
        window.center()
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
        self.window = window
        return window
    }

    /// Switching to `.accessory` can push the window behind other apps.
    private func refront() {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        }
    }
}

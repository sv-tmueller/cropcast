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
    private var loginError: String?

    init(defaults: UserDefaults, loginItem: any LoginItemService) {
        self.defaults = defaults
        self.loginItem = loginItem
        showInDock = DockSetting.load(from: defaults)
        loginRow = LoginItemRow.make(status: loginItem.status, error: nil)
    }

    func refresh() {
        loginRow = LoginItemRow.make(status: loginItem.status, error: loginError)
    }

    func setShowInDock(_ isShown: Bool) {
        DockSetting.save(isShown, to: defaults)
        showInDock = isShown
        DockIcon.apply(isShown: isShown)
        dockDidChange?()
    }

    func setLaunchAtLogin(_ wantOn: Bool) {
        loginError = nil
        do {
            switch LoginItemCommand.for(wantOn: wantOn, status: loginItem.status) {
            case .register: try loginItem.register()
            case .unregister: try loginItem.unregister()
            case .openLoginItems: loginItem.openSystemSettings()
            case .none: break
            }
        } catch {
            loginError = error.localizedDescription
        }
        refresh()
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

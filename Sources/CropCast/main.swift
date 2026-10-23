import AppKit
import CropCastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuController: StatusMenuController?
    private var settings: SettingsWindowController?
    private let dockIcon = DockIcon()
    private var hotKey: GlobalHotKey?
    #if DEBUG
    private var selfTest: SelfTest?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains(SelfTest.flag) {
            selfTest = SelfTest(delegate: self)
            selfTest?.start()
            return
        }
        #endif
        let sharing = SharingController(deps: .live())
        let controller = StatusMenuController(sharing: sharing)
        menuController = controller
        let settings = SettingsWindowController(isFrameLocked: sharing.state.isFrameLocked)
        self.settings = settings
        settings.onSetFrameLock { [weak sharing] in sharing?.setFrameLocked($0) }
        sharing.onLockChange = { [weak settings] in settings?.frameLockDidChange($0) }
        controller.onOpenSettings = { [weak settings] in settings?.show() }
        dockIcon.onOpenSettings = { [weak settings] in settings?.show() }
        dockIcon.installMainMenu()
        hotKey = GlobalHotKey { [weak controller] in
            controller?.apply(.toggleFrame)
        }
    }

    /// A Dock icon click opens Settings. `hasVisibleWindows` is ignored: during a
    /// share the frame panels and the mirror window count as visible.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings?.show()
        return false
    }

    /// Quit tears the session down first (capture, mirror, display) and replies
    /// when that is done, or after 5 s at the latest.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let sharing = menuController?.sharing else { return .terminateNow }
        return sharing.requestQuit() ? .terminateNow : .terminateLater
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    var showInDock = DockSetting.load(from: .standard)
    #if DEBUG
    // The self-test never shows a Dock icon or any Settings UI.
    if CommandLine.arguments.contains(SelfTest.flag) { showInDock = false }
    #endif
    DockIcon.apply(isShown: showInDock)
    // `NSApplication.delegate` is weak, so keep a strong top-level reference.
    let delegate = AppDelegate()
    withExtendedLifetime(delegate) {
        app.delegate = delegate
        app.run()
    }
}

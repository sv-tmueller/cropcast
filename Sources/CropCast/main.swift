import AppKit
import CropCastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuController: StatusMenuController?
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
        let controller = StatusMenuController(sharing: SharingController(deps: .live()))
        menuController = controller
        hotKey = GlobalHotKey { [weak controller] in
            controller?.apply(.toggleFrame)
        }
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
    app.setActivationPolicy(.accessory)
    // `NSApplication.delegate` is weak, so keep a strong top-level reference.
    let delegate = AppDelegate()
    withExtendedLifetime(delegate) {
        app.delegate = delegate
        app.run()
    }
}

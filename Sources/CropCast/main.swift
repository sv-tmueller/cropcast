import AppKit
import CropCastCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusMenuController()
        menuController = controller
        hotKey = GlobalHotKey { [weak controller] in
            controller?.apply(.toggleFrame)
        }
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

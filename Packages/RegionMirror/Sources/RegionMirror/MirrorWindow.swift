import AppKit
import CoreGraphics

/// A borderless, click-through window that covers one display and hosts a
/// ``MirrorView``.
@MainActor
public final class MirrorWindow {
    /// The view frames are rendered into.
    public let view: MirrorView
    private let window: NSWindow

    /// Window number, usable with ``RegionCapture/excludeWindows(_:)``.
    public var windowNumber: Int { window.windowNumber }

    /// Creates a window covering the `NSScreen` of `targetDisplayID`.
    /// - Throws: ``RegionMirrorError/displayNotFound(_:)`` if there is no such screen.
    public init(targetDisplayID: CGDirectDisplayID) throws {
        guard let screen = ScreenLookup.screen(for: targetDisplayID) else {
            throw RegionMirrorError.displayNotFound(targetDisplayID)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: screen.frame.size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: false)

        let view = MirrorView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        self.view = view
        self.window = window
    }

    /// Orders the window to the front without activating the app.
    public func show() {
        window.orderFrontRegardless()
    }

    /// Closes the window.
    public func close() {
        window.close()
    }
}

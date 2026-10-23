import AppKit

/// Receives the mouse interaction of the border panels. Locations are global
/// (`NSEvent.mouseLocation`), so a drag is computed from the start frame plus the
/// total delta and does not depend on the panels moving underneath the cursor.
@MainActor
protocol BorderInteractionDelegate: AnyObject {
    func borderMouseDown(at location: CGPoint)
    func borderMouseDragged(to location: CGPoint)
    func borderMouseUp()
}

/// One of the four thin strips of the frame border. A non-activating, click-through-free
/// panel only over the band, so the interior of the frame is never covered by a window.
final class BorderPanel: NSPanel {
    let borderView: BorderView

    init(delegate: BorderInteractionDelegate?) {
        borderView = BorderView()
        borderView.delegate = delegate
        // `defer: false` gives a valid windowNumber right away.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentView = borderView
        // Set before `level`: changing `isFloatingPanel` resets the level to .floating.
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        ignoresMouseEvents = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    /// Clicking the border must not take focus from the app being shared.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Presets touch the display edges and the menu bar; never let AppKit move the strip.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Draws this panel's part of the band and handles, and forwards mouse events.
final class BorderView: NSView {
    weak var delegate: BorderInteractionDelegate?

    /// The whole frame region in global coordinates; this view draws the part that falls inside it.
    var region: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    /// Only redraws; the style never moves or recreates anything.
    var style: FrameStyle = .idle {
        didSet { if style != oldValue { needsDisplay = true } }
    }

    private static func baseColor(for tint: BorderTint) -> NSColor {
        switch tint {
        case .blue: .systemBlue
        case .red: .systemRed
        }
    }

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let window, !region.isEmpty else { return }
        // The panel's frame is in global coordinates and this view fills the panel.
        let origin = window.frame.origin
        func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -origin.x, dy: -origin.y) }

        let base = Self.baseColor(for: style.tint)
        base.withAlphaComponent(0.55).setFill()
        bounds.fill()

        base.setFill()
        for handle in FrameHandle.allCases {
            for rect in BorderLayout.handleRects(for: handle, in: region) {
                let visible = local(rect).intersection(bounds)
                if !visible.isNull && !visible.isEmpty { visible.fill() }
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        delegate?.borderMouseDown(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        delegate?.borderMouseDragged(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.borderMouseUp()
    }
}

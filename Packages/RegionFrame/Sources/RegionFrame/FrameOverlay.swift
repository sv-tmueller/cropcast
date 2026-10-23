import AppKit

/// The region the frame currently marks. `rect` is in AppKit global coordinates
/// (bottom-left origin, points); `displayID` is the display it lies on.
public struct FrameRegion: Equatable, Sendable {
    public var displayID: CGDirectDisplayID
    public var rect: CGRect

    public init(displayID: CGDirectDisplayID, rect: CGRect) {
        self.displayID = displayID
        self.rect = rect
    }
}

/// The movable, resizable 16:9 frame drawn on a display.
///
/// The frame is four thin border panels placed *inside* the region rect, so no
/// window covers the interior: clicks, scrolls and drags always reach the app below.
/// The region is clamped to the display it is on; it only changes display through
/// `show(on:)` or `apply(preset:on:)`.
@MainActor
public final class FrameOverlay {
    /// Called on first placement, on every drag step that changes the rect and on
    /// each preset. Identical regions are skipped.
    public var regionDidChange: ((FrameRegion) -> Void)?

    /// The current region; nil until the frame was placed for the first time.
    public private(set) var region: FrameRegion?

    public private(set) var isVisible = false

    /// How the frame is drawn: `.idle` (blue, default) or `.live` (red, a share
    /// session is running). Changing it only redraws the four existing panels. It
    /// never places, saves, shows or hides the frame, never fires `regionDidChange`,
    /// never writes the persisted state and never recreates a panel, so
    /// `windowNumbers` stay valid for a capture filter. It can be set while the
    /// frame is hidden, and `show(on:)`, `hide()` and `apply(preset:on:)` keep it.
    public var style: FrameStyle = .idle {
        didSet {
            guard style != oldValue else { return }
            for panel in panels { panel.borderView.style = style }
        }
    }

    /// Window numbers of the four border panels (top, bottom, left, right).
    /// Stable across show/hide, so a capture filter can exclude them.
    public var windowNumbers: [Int] { panels.map(\.windowNumber) }

    private let store: FrameStore
    private let interaction = InteractionBridge()
    let panels: [BorderPanel]
    private var drag: Drag?
    private var isPlacing = false

    private struct Drag {
        let zone: BorderZone
        let startRect: CGRect
        let startMouse: CGPoint
        let displayID: CGDirectDisplayID
    }

    /// - Parameter defaults: where the last region per display is persisted. The app
    ///   passes `.standard`; the demo and tests pass their own suite.
    public init(defaults: UserDefaults = .standard) {
        store = FrameStore(defaults: defaults)
        panels = BorderEdge.allCases.map { _ in BorderPanel(delegate: nil) }
        // Edge order of `panels` follows `BorderEdge.allCases`.
        for panel in panels {
            panel.borderView.delegate = interaction
            panel.delegate = interaction
        }
        interaction.owner = self
    }

    /// Shows the frame on `display`. If that display is not connected, nothing
    /// happens: the frame state and visibility stay as they were and
    /// `regionDidChange` does not fire. Without `display` it uses the last saved
    /// display that is still connected, else the one under the mouse, else the
    /// first. Batch 2 should always pass the display explicitly.
    public func show(on display: CGDirectDisplayID? = nil) {
        guard let target = resolveDisplay(display) else { return }
        if let current = region, current.displayID == target.id {
            place(FrameRegion(displayID: target.id, rect: FrameGeometry.clamp(current.rect, to: target.screen.frame)))
        } else {
            let state = store.load()
            let key = DisplayIdentity.key(for: target.id)
            let rect = FrameGeometry.restore(local: state.localRect(forDisplay: key), in: target.screen.frame)
            place(FrameRegion(displayID: target.id, rect: rect))
        }
        for panel in panels { panel.orderFrontRegardless() }
        isVisible = true
        save()
    }

    public func hide() {
        drag = nil
        for panel in panels { panel.orderOut(nil) }
        isVisible = false
    }

    /// Moves the frame to a preset slot of `display` (default: as in `show(on:)`).
    /// If `display` is not connected, nothing happens: the frame state is
    /// unchanged and `regionDidChange` does not fire.
    /// Never changes whether the frame is visible.
    public func apply(preset: RegionPreset, on display: CGDirectDisplayID? = nil) {
        guard let target = resolveDisplay(display) else { return }
        place(FrameRegion(displayID: target.id, rect: FrameGeometry.preset(preset, in: target.screen.frame)))
        save()
    }

    // MARK: - Placement and persistence

    private func place(_ new: FrameRegion) {
        let changed = region != new
        region = new
        layOutPanels(for: new.rect)
        if changed { regionDidChange?(new) }
    }

    private func layOutPanels(for rect: CGRect) {
        isPlacing = true
        defer { isPlacing = false }
        for (panel, edge) in zip(panels, BorderEdge.allCases) {
            panel.setFrame(BorderLayout.strip(for: edge, in: rect), display: true)
            panel.borderView.region = rect
        }
    }

    /// Backstop: a strip was moved or resized from outside. Restores all four to
    /// the current region. Never fires `regionDidChange`, never saves.
    fileprivate func panelFrameDidChange() {
        guard !isPlacing, let region else { return }
        let inPlace = zip(panels, BorderEdge.allCases).allSatisfy { $0.frame == BorderLayout.strip(for: $1, in: region.rect) }
        if !inPlace { layOutPanels(for: region.rect) }
    }

    private func save() {
        guard let region, let screen = DisplayIdentity.screen(for: region.displayID) else { return }
        var state = store.load()
        let local = region.rect.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        state.record(localRect: local, forDisplay: DisplayIdentity.key(for: region.displayID))
        store.save(state)
    }

    /// Picks the display via `DisplayChoice`: an explicit id must be connected (else
    /// nil, so the caller does nothing); without one, the last saved display still
    /// connected, else the display under the mouse, else the first.
    private func resolveDisplay(_ requested: CGDirectDisplayID?) -> (id: CGDirectDisplayID, screen: NSScreen)? {
        let screens = NSScreen.screens.compactMap { screen in
            DisplayIdentity.displayID(of: screen).map { (id: $0, screen: screen) }
        }
        let lastKey = store.load().lastDisplayKey
        let lastSaved = screens.first { lastKey != nil && DisplayIdentity.key(for: $0.id) == lastKey }?.id
        let mouse = NSEvent.mouseLocation
        let underMouse = screens.first { $0.screen.frame.contains(mouse) }?.id
        guard let id = DisplayChoice.pick(
            requested: requested,
            connected: screens.map(\.id),
            lastSaved: lastSaved,
            underMouse: underMouse
        ), let found = screens.first(where: { $0.id == id }) else { return nil }
        return (id, found.screen)
    }

    // MARK: - Mouse interaction

    fileprivate func mouseDown(at location: CGPoint) {
        guard let region, let zone = BorderLayout.zone(at: location, in: region.rect) else {
            drag = nil
            return
        }
        drag = Drag(zone: zone, startRect: region.rect, startMouse: location, displayID: region.displayID)
    }

    fileprivate func mouseDragged(to location: CGPoint) {
        guard let drag, let screen = DisplayIdentity.screen(for: drag.displayID) else { return }
        let delta = CGVector(dx: location.x - drag.startMouse.x, dy: location.y - drag.startMouse.y)
        let rect: CGRect
        switch drag.zone {
        case .move: rect = FrameGeometry.move(drag.startRect, by: delta, in: screen.frame)
        case .resize(let handle): rect = FrameGeometry.resize(drag.startRect, handle: handle, by: delta, in: screen.frame)
        }
        if rect != region?.rect { place(FrameRegion(displayID: drag.displayID, rect: rect)) }
    }

    fileprivate func mouseUp() {
        guard drag != nil else { return }
        drag = nil
        save()
    }
}

/// Keeps the border protocol and window delegate conformances out of the public class.
@MainActor
private final class InteractionBridge: NSObject, BorderInteractionDelegate, NSWindowDelegate {
    weak var owner: FrameOverlay?

    func borderMouseDown(at location: CGPoint) { owner?.mouseDown(at: location) }
    func borderMouseDragged(to location: CGPoint) { owner?.mouseDragged(to: location) }
    func borderMouseUp() { owner?.mouseUp() }

    func windowDidMove(_ notification: Notification) { owner?.panelFrameDidChange() }
    func windowDidResize(_ notification: Notification) { owner?.panelFrameDidChange() }
}

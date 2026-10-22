import CoreGraphics
import Foundation

internal import CVirtualDisplayShim

/// Why a virtual display could not be started.
public enum VirtualDisplayError: Error, Equatable, Sendable {
    /// The private CGVirtualDisplay API is missing or has a different shape on
    /// this macOS version.
    case apiUnavailable(String)
    /// The API exists but the system refused to create the display.
    case creationFailed(String)
    /// The display was created but the system rejected its mode settings.
    case settingsRejected
    /// The display never appeared in the active display list.
    case didNotComeOnline
    /// Moving the display into place in the arrangement failed.
    case placementFailed(CGError)
}

extension VirtualDisplayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .apiUnavailable(let detail):
            return "The virtual display API is unavailable: \(detail)"
        case .creationFailed(let detail):
            return "The virtual display could not be created: \(detail)"
        case .settingsRejected:
            return "The system rejected the virtual display's mode settings."
        case .didNotComeOnline:
            return "The virtual display did not come online in time. A common cause is a host process that does not run the AppKit event loop (NSApplication.run()) for its whole life once it calls start()."
        case .placementFailed(let error):
            return "The virtual display could not be placed in the display arrangement (CGError \(error.rawValue))."
        }
    }
}

/// Names of the private classes, injectable so tests can exercise failure
/// paths without ever creating a real display.
struct ShimClassNames: Sendable {
    var display: String
    var descriptor: String
    var mode: String
    var settings: String

    static let standard = ShimClassNames(
        display: "CGVirtualDisplay",
        descriptor: "CGVirtualDisplayDescriptor",
        mode: "CGVirtualDisplayMode",
        settings: "CGVirtualDisplaySettings")
}

/// A 2560x1440 @ 60 Hz, non-HiDPI virtual display named "CropCast".
///
/// The display exists for as long as this object does: `stop()` or releasing
/// the last reference removes it. Sleep and display-change handling
/// (`terminationHandler`) is intentionally not exposed; the integration batch
/// owns that.
///
/// The process must run the AppKit event loop (`NSApplication.run()`, as the
/// menu bar app does) for the rest of its life once it calls `start()`, not
/// only while a display exists. Under Swift's async main or a bare
/// `CFRunLoopRun()`, CoreGraphics stops updating this process's display list
/// after the placement transaction: `stop()` still removes the display
/// system-wide, but `CGGetActiveDisplayList` in this process keeps listing it,
/// so the next `start()` throws `.didNotComeOnline`.
@MainActor
public final class VirtualDisplay {
    static let name = "CropCast"
    static let width: UInt32 = 2560
    static let height: UInt32 = 1440
    static let refreshRate: Double = 60

    public let displayID: CGDirectDisplayID
    /// Where `start()` asked macOS to put the display (CoreGraphics global
    /// coordinates). macOS may adjust it; compare with `CGDisplayBounds`.
    public private(set) var requestedOrigin: CGPoint = .zero
    private var shim: VirtualDisplayShim?

    private init(shim: VirtualDisplayShim) {
        self.displayID = shim.displayID
        self.shim = shim
    }

    /// Creates the display, waits for it to come online and places it at the
    /// bottom-left corner of the main display. All-or-nothing: on failure
    /// nothing is left behind.
    public static func start() async throws(VirtualDisplayError) -> VirtualDisplay {
        try await start(classNames: .standard)
    }

    static func start(classNames: ShimClassNames) async throws(VirtualDisplayError) -> VirtualDisplay {
        let shim: VirtualDisplayShim
        do {
            shim = try VirtualDisplayShim.create(
                withName: name, width: width, height: height, refreshRate: refreshRate,
                displayClassName: classNames.display,
                descriptorClassName: classNames.descriptor,
                modeClassName: classNames.mode,
                settingsClassName: classNames.settings)
        } catch {
            throw mapShimError(error as NSError)
        }

        // From here on, any failure drops `display`, which releases the shim
        // and removes the display again.
        let display = VirtualDisplay(shim: shim)
        guard await display.waitUntilOnline() else {
            throw .didNotComeOnline
        }
        try display.place()
        return display
    }

    /// Removes the display. Safe to call more than once.
    public func stop() {
        shim = nil
    }

    // MARK: - Private

    static func mapShimError(_ error: NSError) -> VirtualDisplayError {
        let message = error.localizedDescription
        guard error.domain == CVDShimErrorDomain,
            let code = CVDShimError.Code(rawValue: error.code)
        else {
            return .creationFailed(message)
        }
        switch code {
        case .apiUnavailable: return .apiUnavailable(message)
        case .creationFailed: return .creationFailed(message)
        case .settingsRejected: return .settingsRejected
        @unknown default: return .creationFailed(message)
        }
    }

    private func waitUntilOnline() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if Self.activeDisplayIDs().contains(displayID) { return true }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return Self.activeDisplayIDs().contains(displayID)
    }

    private func place() throws(VirtualDisplayError) {
        let main = CGDisplayBounds(CGMainDisplayID())
        let origin = Placement.origin(
            mainBounds: main,
            displaySize: CGSize(width: Double(Self.width), height: Double(Self.height)))
        requestedOrigin = origin

        var config: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&config)
        guard error == .success, let config else { throw .placementFailed(error) }
        error = CGConfigureDisplayOrigin(config, displayID, Int32(origin.x), Int32(origin.y))
        guard error == .success else {
            CGCancelDisplayConfiguration(config)
            throw .placementFailed(error)
        }
        error = CGCompleteDisplayConfiguration(config, .forSession)
        guard error == .success else { throw .placementFailed(error) }
    }

    static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}

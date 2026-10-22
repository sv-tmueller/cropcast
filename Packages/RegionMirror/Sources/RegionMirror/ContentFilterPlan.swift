import CoreGraphics

/// Decides how the capture content filter excludes CropCast's own windows.
///
/// Pure value logic so the rule is unit-tested without ScreenCaptureKit.
///
/// Rule: whenever this app is listed in the shareable content, the whole app is
/// excluded via `SCContentFilter(display:excludingApplications:exceptingWindows:)`,
/// so windows created after the filter was built (overlays, a second mirror
/// window) are hidden too. For an application in the exclusion list, an
/// exception window is hidden when its owning app is NOT in the list and shown
/// when it is (SCStream.h). So extra windows owned by other apps go into
/// `exceptingWindows` and are hidden, while our own windows are never put there.
/// Listing our own windows one by one (`excludingWindows:`) is only the fallback
/// for when this app is missing from the shareable content.
///
/// `App` is the application value (`SCRunningApplication` in production). The
/// app-exclusion case carries it, so "exclude the app" cannot be expressed
/// without having the app: there is no fail-open state.
enum ContentFilterPlan<App: Equatable>: Equatable {
    /// `excludingApplications: [app], exceptingWindows: <ids>`.
    case excludingApp(App, exceptingWindows: [CGWindowID])
    /// `excludingWindows: <ids>`; used only when this app is not listed.
    case excludingWindows([CGWindowID])

    /// The window fields the decision needs.
    struct Window: Equatable {
        let windowID: CGWindowID
        let processID: pid_t
    }

    static func make(
        ownProcessID: pid_t,
        selfApp: App?,
        windows: [Window],
        extraWindowIDs: [CGWindowID]
    ) -> ContentFilterPlan {
        let foreignExtras =
            windows
            .filter { extraWindowIDs.contains($0.windowID) && $0.processID != ownProcessID }
            .map(\.windowID)
        if let selfApp {
            return .excludingApp(selfApp, exceptingWindows: foreignExtras)
        }
        let ownWindows = windows.filter { $0.processID == ownProcessID }.map(\.windowID)
        return .excludingWindows(ownWindows + foreignExtras)
    }
}

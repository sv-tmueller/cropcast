import CropCastCore
import ServiceManagement

/// The system side of "Launch at login". Thin on purpose: every decision
/// (what the row shows, what a flip does) lives in `CropCastCore.LoginItem`.
@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// `SMAppService.mainApp`. It registers the running bundle's path, so only an
/// installed `CropCast.app` can use it; `swift run` reports `.notFound`.
struct LiveLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

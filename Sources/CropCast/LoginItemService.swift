import CropCastCore
import Foundation
import OSLog
import ServiceManagement

/// The system side of "Launch at login". Thin on purpose: every decision
/// (what the row shows, what a flip does) lives in `CropCastCore.LoginItem`.
@MainActor
protocol LoginItemService {
    var status: LoginItemStatus { get }
    /// True when running from a `.app` bundle. `swift run` and
    /// `.build/debug/CropCast` are not, and cannot register a login item.
    var isAppBundle: Bool { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// `SMAppService.mainApp`. It registers the running bundle's path, so only an
/// installed `CropCast.app` can use it. An unbundled run reports `.notFound`,
/// and so does an installed app that was never registered; `isAppBundle` tells
/// them apart.
///
/// Every status read and call is logged (subsystem
/// `com.github.sv-tmueller.cropcast`, category `login-item`) with public
/// fields, so `/usr/bin/log show` prints them instead of `<private>`.
struct LiveLoginItemService: LoginItemService {
    private static let log = Logger(subsystem: "com.github.sv-tmueller.cropcast", category: "login-item")

    var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var status: LoginItemStatus {
        let raw = SMAppService.mainApp.status
        let mapped: LoginItemStatus
        switch raw {
        case .enabled: mapped = .enabled
        case .notRegistered: mapped = .notRegistered
        case .requiresApproval: mapped = .requiresApproval
        case .notFound: mapped = .notFound
        @unknown default: mapped = .notFound
        }
        Self.log.notice(
            "status \(mapped.name, privacy: .public) (raw \(raw.rawValue, privacy: .public)) bundle \(Bundle.main.bundlePath, privacy: .public)"
        )
        return mapped
    }

    func register() throws {
        Self.log.notice("register start")
        do {
            try SMAppService.mainApp.register()
            Self.log.notice("register ok")
        } catch {
            Self.logFailure("register", error)
            throw error
        }
    }

    func unregister() throws {
        Self.log.notice("unregister start")
        do {
            try SMAppService.mainApp.unregister()
            Self.log.notice("unregister ok")
        } catch {
            Self.logFailure("unregister", error)
            throw error
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func logFailure(_ action: String, _ error: any Error) {
        let ns = error as NSError
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        log.error(
            "\(action, privacy: .public) failed: \(ns.domain, privacy: .public) \(ns.code, privacy: .public) \(ns.localizedDescription, privacy: .public) underlying \(underlying?.domain ?? "none", privacy: .public) \(underlying?.code ?? 0, privacy: .public)"
        )
    }
}

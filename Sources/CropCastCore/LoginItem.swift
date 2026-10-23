import Foundation

/// Mirrors `SMAppService.Status`; the app glue maps it.
public enum LoginItemStatus: Sendable, Equatable {
    case enabled, notRegistered, requiresApproval, notFound

    /// The case name, for logs and notes.
    public var name: String {
        switch self {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .requiresApproval: return "requiresApproval"
        case .notFound: return "notFound"
        }
    }
}

/// What the "Launch at login" row shows.
public struct LoginItemRow: Sendable, Equatable {
    public var isOn: Bool
    public var isEnabled: Bool
    public var note: String?
    public var showsOpenLoginItems: Bool

    public init(isOn: Bool, isEnabled: Bool, note: String?, showsOpenLoginItems: Bool) {
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.note = note
        self.showsOpenLoginItems = showsOpenLoginItems
    }

    /// The switch shows the real system state: on only when `.enabled`. A
    /// register or unregister `error` text replaces the status note.
    ///
    /// `.notFound` means two things: an unbundled run (`swift run`), or an
    /// installed app that was never registered ("record not found"). Only the
    /// second can be fixed from here, by registering, so inside an app bundle
    /// `.notFound` behaves like `.notRegistered`.
    public static func make(status: LoginItemStatus, isAppBundle: Bool, error: String?) -> LoginItemRow {
        var row = LoginItemRow(isOn: false, isEnabled: true, note: nil, showsOpenLoginItems: false)
        switch status {
        case .enabled:
            row.isOn = true
        case .notRegistered:
            break
        case .notFound where isAppBundle:
            break
        case .requiresApproval:
            row.note = "Approve CropCast in System Settings > General > Login Items."
            row.showsOpenLoginItems = true
        case .notFound:
            row.isEnabled = false
            row.note = "Launch at login needs the installed CropCast.app."
        }
        if let error { row.note = error }
        return row
    }
}

/// What flipping the "Launch at login" switch has to do.
public enum LoginItemCommand: Sendable, Equatable {
    case register, unregister, openLoginItems, none

    public static func `for`(wantOn: Bool, status: LoginItemStatus, isAppBundle: Bool) -> LoginItemCommand {
        switch (wantOn, status) {
        case (_, .notFound) where !isAppBundle: return .none
        case (true, .notRegistered), (true, .notFound): return .register
        case (true, .requiresApproval): return .openLoginItems
        case (false, .enabled), (false, .requiresApproval): return .unregister
        case (true, .enabled), (false, .notRegistered), (false, .notFound): return .none
        }
    }
}

/// Why a register or unregister did not do what was asked. It outlives status
/// refreshes until a status read shows the requested state, so a failure is
/// never wiped by the very refresh that follows it.
public struct LoginItemNote: Sendable, Equatable {
    public var wantOn: Bool
    public var text: String

    public init(wantOn: Bool, text: String) {
        self.wantOn = wantOn
        self.text = text
    }

    /// The call threw. Always names the domain and code, so the text is never
    /// empty even when the system gives no description.
    public static func failure(wantOn: Bool, domain: String, code: Int, description: String) -> LoginItemNote {
        let verb = wantOn ? "on" : "off"
        let detail = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = detail.isEmpty
            ? "Could not turn \(verb) Launch at login (\(domain) \(code))."
            : "Could not turn \(verb) Launch at login: \(detail) (\(domain) \(code))."
        return LoginItemNote(wantOn: wantOn, text: text)
    }

    /// The call did not throw but the status read afterwards disagrees. A
    /// `.requiresApproval` status needs no text: its own note and button
    /// already cover it.
    public static func check(wantOn: Bool, status: LoginItemStatus) -> LoginItemNote? {
        switch (wantOn, status) {
        case (true, .notRegistered), (true, .notFound):
            return LoginItemNote(
                wantOn: true,
                text: "macOS did not add CropCast to Login Items (status: \(status.name)). Details are in the log.")
        case (false, .enabled):
            return LoginItemNote(
                wantOn: false,
                text: "macOS did not remove CropCast from Login Items (status: enabled). Details are in the log.")
        default:
            return nil
        }
    }

    /// True once a status read shows the state that was asked for.
    public func isResolved(by status: LoginItemStatus) -> Bool {
        wantOn == (status == .enabled)
    }
}

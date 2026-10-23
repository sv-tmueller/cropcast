/// Mirrors `SMAppService.Status`; the app glue maps it.
public enum LoginItemStatus: Sendable, Equatable {
    case enabled, notRegistered, requiresApproval, notFound
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
    public static func make(status: LoginItemStatus, error: String?) -> LoginItemRow {
        var row = LoginItemRow(isOn: false, isEnabled: true, note: nil, showsOpenLoginItems: false)
        switch status {
        case .enabled:
            row.isOn = true
        case .notRegistered:
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

    public static func `for`(wantOn: Bool, status: LoginItemStatus) -> LoginItemCommand {
        switch (wantOn, status) {
        case (_, .notFound): return .none
        case (true, .notRegistered): return .register
        case (true, .requiresApproval): return .openLoginItems
        case (false, .enabled), (false, .requiresApproval): return .unregister
        case (true, .enabled), (false, .notRegistered): return .none
        }
    }
}

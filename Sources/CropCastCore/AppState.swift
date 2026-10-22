/// One of the three full-height 16:9 slots on the ultrawide display.
public enum FramePreset: CaseIterable, Sendable, Equatable {
    case left, center, right
}

/// A command the user can trigger from the menu bar or the global hotkey.
public enum MenuAction: Sendable, Equatable {
    case toggleSharing
    case toggleFrame
    case selectPreset(FramePreset)
    case quit
}

/// Pure description of one menu row, rendered to `NSMenu` by the app glue.
public enum MenuEntry: Sendable, Equatable {
    case item(title: String, action: MenuAction)
    case separator
    case submenu(title: String, entries: [MenuEntry])
}

/// App-level state shown in the menu bar. Pure Swift: no AppKit.
public struct AppState: Sendable, Equatable {
    public private(set) var session = SessionMachine()
    /// The glue reads this back from the frame overlay after every overlay call.
    public var isFrameVisible = false
    public var lastPreset: FramePreset?

    public init() {}

    public var phase: SessionPhase { session.phase }
    public var isSharing: Bool { phase == .sharing }

    /// Applies a user command and returns what the glue has to do about the
    /// sharing session. `.quit` does not change state: the glue terminates the
    /// app, and `applicationShouldTerminate` reports it as `.quitRequested`.
    @discardableResult
    public mutating func apply(_ action: MenuAction) -> [SessionEffect] {
        switch action {
        case .toggleSharing:
            return session.handle(.toggleSharing)
        case .toggleFrame:
            isFrameVisible.toggle()
        case .selectPreset(let preset):
            lastPreset = preset
        case .quit:
            break
        }
        return []
    }

    /// Feeds a session event (start/stop outcome, quit request) to the machine.
    @discardableResult
    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        session.handle(event)
    }

    /// The menu for the current state, in display order.
    public func menuEntries() -> [MenuEntry] {
        [
            .item(title: sharingTitle, action: .toggleSharing),
            .item(title: isFrameVisible ? "Hide Frame" : "Show Frame", action: .toggleFrame),
            .separator,
            .submenu(title: "Presets", entries: [
                .item(title: "Left", action: .selectPreset(.left)),
                .item(title: "Center", action: .selectPreset(.center)),
                .item(title: "Right", action: .selectPreset(.right)),
            ]),
            .separator,
            .item(title: "Quit CropCast", action: .quit),
        ]
    }

    private var sharingTitle: String {
        switch phase {
        case .idle: return "Start Sharing"
        case .starting: return "Starting…"
        case .sharing: return "Stop Sharing"
        case .stopping: return "Stopping…"
        }
    }
}

/// One of the three full-height 16:9 slots on the ultrawide display.
public enum FramePreset: CaseIterable, Sendable, Equatable {
    case left, center, right
}

/// A command the user can trigger from the menu bar or the global hotkey.
public enum MenuAction: Sendable, Equatable {
    case toggleSharing
    case toggleFrame
    case selectPreset(FramePreset)
    /// Choose the source display by its stable key (the display UUID string).
    case selectDisplay(key: String)
    case quit
    case openSettings

    /// Menu key equivalent (Command is implied).
    public var keyEquivalent: String {
        switch self {
        case .quit: return "q"
        case .openSettings: return ","
        case .toggleSharing, .toggleFrame, .selectPreset, .selectDisplay: return ""
        }
    }
}

/// Pure description of one menu row, rendered to `NSMenu` by the app glue.
public enum MenuEntry: Sendable, Equatable {
    case item(title: String, action: MenuAction)
    /// An item with a checkmark.
    case checkable(title: String, action: MenuAction, isChecked: Bool)
    case separator
    case submenu(title: String, entries: [MenuEntry], isEnabled: Bool = true)
}

/// The menu bar icon for a state: an SF Symbol name and its accessibility
/// description. The app renders it as a template image.
public struct StatusIcon: Sendable, Equatable {
    public let symbolName: String
    public let accessibilityDescription: String
    public let isLive: Bool

    public static let idle = StatusIcon(
        symbolName: "rectangle.dashed", accessibilityDescription: "CropCast", isLive: false)
    public static let live = StatusIcon(
        symbolName: "rectangle.dashed.badge.record",
        accessibilityDescription: "CropCast, sharing live", isLive: true)
}

/// App-level state shown in the menu bar. Pure Swift: no AppKit.
public struct AppState: Sendable, Equatable {
    public private(set) var session = SessionMachine()
    /// The glue reads this back from the frame overlay after every overlay call.
    public var isFrameVisible = false
    public var lastPreset: FramePreset?
    /// The display chosen in the Display menu. Only `.selectDisplay` changes
    /// it; it can name a display that is not connected right now.
    public private(set) var chosenDisplayKey: String?

    public init(chosenDisplayKey: String? = nil) {
        self.chosenDisplayKey = chosenDisplayKey
    }

    public var phase: SessionPhase { session.phase }
    public var isSharing: Bool { phase == .sharing }
    /// The menu bar icon: badged from Starting… through Stopping…, plain when idle.
    public var statusIcon: StatusIcon { phase.isLive ? .live : .idle }
    /// The source display can only change while no session is running.
    public var canChooseDisplay: Bool { phase == .idle }

    /// Applies a user command and returns what the glue has to do about the
    /// sharing session. `.quit` does not change state: the glue terminates the
    /// app, and `applicationShouldTerminate` reports it as `.quitRequested`.
    /// `.openSettings` does not either: the glue opens the window.
    @discardableResult
    public mutating func apply(_ action: MenuAction) -> [SessionEffect] {
        switch action {
        case .toggleSharing:
            return session.handle(.toggleSharing)
        case .toggleFrame:
            isFrameVisible.toggle()
        case .selectPreset(let preset):
            lastPreset = preset
        case .selectDisplay(let key):
            if canChooseDisplay { chosenDisplayKey = key }
        case .quit, .openSettings:
            break
        }
        return []
    }

    /// Feeds a session event (start/stop outcome, quit request) to the machine.
    @discardableResult
    public mutating func handle(_ event: SessionEvent) -> [SessionEffect] {
        session.handle(event)
    }

    /// The menu for the current state, in display order. `displays` are the
    /// connected displays in `NSScreen.screens` order; `excluding` (the virtual
    /// displays) is left out of the Display submenu.
    public func menuEntries(
        displays: [DisplayCandidate] = [], excluding: Set<UInt32> = []
    ) -> [MenuEntry] {
        let shown = displays.filter { !excluding.contains($0.id) }
        let checked = SourceDisplayChoice.pick(
            from: shown, excluding: [], chosenKey: chosenDisplayKey)
        return [
            .item(title: sharingTitle, action: .toggleSharing),
            .item(title: isFrameVisible ? "Hide Frame" : "Show Frame", action: .toggleFrame),
            .separator,
            .submenu(
                title: "Display",
                entries: shown.map {
                    .checkable(
                        title: $0.name, action: .selectDisplay(key: $0.key),
                        isChecked: $0.id == checked)
                },
                isEnabled: canChooseDisplay),
            .submenu(title: "Presets", entries: [
                .item(title: "Left", action: .selectPreset(.left)),
                .item(title: "Center", action: .selectPreset(.center)),
                .item(title: "Right", action: .selectPreset(.right)),
            ]),
            .separator,
            .item(title: "Settings…", action: .openSettings),
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

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
    public var isSharing = false
    public var isFrameVisible = false
    public var lastPreset: FramePreset?

    public init() {}

    /// Applies a user command. `.quit` does not change state; the glue terminates the app.
    public mutating func apply(_ action: MenuAction) {
        switch action {
        case .toggleSharing:
            isSharing.toggle()
        case .toggleFrame:
            isFrameVisible.toggle()
        case .selectPreset(let preset):
            lastPreset = preset
        case .quit:
            break
        }
    }

    /// The menu for the current state, in display order.
    public func menuEntries() -> [MenuEntry] {
        [
            .item(title: isSharing ? "Stop Sharing" : "Start Sharing", action: .toggleSharing),
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
}

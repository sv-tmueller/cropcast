/// How the frame is drawn. `.idle` is the normal blue frame; `.live` is red and
/// marks that a share session is running (the app switches it, see `FrameOverlay.style`).
public enum FrameStyle: Sendable, Equatable, CaseIterable {
    case idle
    case live
}

/// The color family of a style. Kept free of AppKit so the rule is unit testable:
/// comparing dynamic system colors is unreliable.
enum BorderTint: Equatable {
    case blue
    case red
}

extension FrameStyle {
    var tint: BorderTint {
        switch self {
        case .idle: .blue
        case .live: .red
        }
    }
}

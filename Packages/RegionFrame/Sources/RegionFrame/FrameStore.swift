import CoreGraphics
import Foundation

/// A rect stored as plain numbers so the on-disk format does not depend on
/// `CGRect`'s own encoding.
struct StoredRect: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.minX
        y = rect.minY
        width = rect.width
        height = rect.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// The persisted state: the last used display and one frame per display.
/// Rects are measured from the display's origin, so they survive an arrangement change.
struct FrameState: Codable, Equatable {
    static let currentVersion = 1

    var version = FrameState.currentVersion
    var lastDisplayKey: String?
    var frames: [String: StoredRect] = [:]

    func localRect(forDisplay key: String) -> CGRect? {
        frames[key]?.rect
    }

    /// Stores `localRect` for the display and marks it as the last used one.
    mutating func record(localRect: CGRect, forDisplay key: String) {
        frames[key] = StoredRect(localRect)
        lastDisplayKey = key
    }
}

/// Reads and writes `FrameState` as one versioned JSON blob in the given defaults.
/// The module never picks the defaults itself: the app passes `.standard`, the
/// demo and the tests pass their own suites.
struct FrameStore {
    static let key = "RegionFrame.state.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The stored state; empty when nothing is stored, the data cannot be decoded
    /// or it has an unknown version. Never throws or crashes.
    func load() -> FrameState {
        guard let data = defaults.data(forKey: Self.key),
              let state = try? JSONDecoder().decode(FrameState.self, from: data),
              state.version == FrameState.currentVersion
        else { return FrameState() }
        return state
    }

    func save(_ state: FrameState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

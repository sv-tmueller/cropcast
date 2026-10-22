import CoreGraphics

/// Pure decision of which display the frame goes on.
enum DisplayChoice {
    /// - An explicit `requested` display is used if it is connected; otherwise
    ///   nothing is picked (the caller does nothing). It never falls back.
    /// - Without `requested`: `lastSaved` if connected, else `underMouse` if
    ///   connected, else the first connected display.
    static func pick(
        requested: CGDirectDisplayID?,
        connected: [CGDirectDisplayID],
        lastSaved: CGDirectDisplayID?,
        underMouse: CGDirectDisplayID?
    ) -> CGDirectDisplayID? {
        if let requested { return connected.contains(requested) ? requested : nil }
        for candidate in [lastSaved, underMouse] {
            if let candidate, connected.contains(candidate) { return candidate }
        }
        return connected.first
    }
}

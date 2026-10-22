import CoreGraphics

/// A full-height 16:9 slot on a display. Named `RegionPreset` (not `FramePreset`)
/// so it never clashes with other modules' types.
public enum RegionPreset: CaseIterable, Sendable {
    case left, center, right
}

/// Pure 16:9 frame geometry in AppKit global coordinates (bottom-left origin).
///
/// "Exactly 16:9" means `width = 16k` and `height = 9k` with `k` a whole number
/// of points, so `width * 9 == height * 16` is an exact check. The frame never
/// leaves the display it is on (`NSScreen.frame`, not `visibleFrame`, so a
/// 2560x1440 slot fits on a 1440 pt tall display under the menu bar).
public enum FrameGeometry {
    /// Smallest allowed `k`: 640x360.
    public static let minK = 40

    /// Largest `k` for which a 16k x 9k frame fits on `display`.
    public static func maxK(in display: CGRect) -> Int {
        max(1, wholeCount(min(display.width / 16, display.height / 9).rounded(.down)))
    }

    /// Clamps any rect: snaps its size to the 16:9 steps (keeping the origin),
    /// then shifts it inside `display`.
    public static func clamp(_ rect: CGRect, to display: CGRect) -> CGRect {
        let bounds = wholeBounds(of: display)
        let rect = sanitized(rect, in: bounds)
        let k = limitedK(wholeCount((rect.width / 16).rounded()), upTo: maxK(in: bounds))
        return fitted(origin: CGPoint(x: rect.minX.rounded(), y: rect.minY.rounded()), k: k, in: bounds)
    }

    /// Moves `rect` by the rounded `delta`, then pushes it back inside `display`.
    public static func move(_ rect: CGRect, by delta: CGVector, in display: CGRect) -> CGRect {
        let rect = sanitized(rect, in: wholeBounds(of: display))
        return clamp(rect.offsetBy(dx: bounded(delta.dx, fallback: 0).rounded(), dy: bounded(delta.dy, fallback: 0).rounded()), to: display)
    }

    /// Resizes `rect` by dragging `handle` by the *total* `delta` since the drag began.
    ///
    /// Corner handles keep the opposite corner fixed; the dominant drag axis
    /// decides the size. Edge handles keep the opposite edge fixed, only the drag
    /// along that axis counts, and the other dimension stays centred on the old
    /// centre (shifted, not shrunk, to stay inside the display).
    public static func resize(_ rect: CGRect, handle: FrameHandle, by delta: CGVector, in display: CGRect) -> CGRect {
        let bounds = wholeBounds(of: display)
        let rect = sanitized(rect, in: bounds)
        let delta = CGVector(dx: bounded(delta.dx, fallback: 0), dy: bounded(delta.dy, fallback: 0))
        let dir = direction(of: handle)

        // Room between the fixed side and the display edge on each axis (never
        // more than the display itself, even if `rect` starts outside it).
        let roomW = min(dir.x > 0 ? bounds.maxX - rect.minX : rect.maxX - bounds.minX, bounds.width)
        let roomH = min(dir.y > 0 ? bounds.maxY - rect.minY : rect.maxY - bounds.minY, bounds.height)

        let rawK: Int
        let kMax: Int
        if dir.x != 0 && dir.y != 0 {
            let widthWins = abs(delta.dx) * 9 >= abs(delta.dy) * 16
            rawK = widthWins
                ? wholeCount(((rect.width + dir.x * delta.dx) / 16).rounded())
                : wholeCount(((rect.height + dir.y * delta.dy) / 9).rounded())
            kMax = wholeCount(min(roomW / 16, roomH / 9).rounded(.down))
        } else if dir.x != 0 {
            rawK = wholeCount(((rect.width + dir.x * delta.dx) / 16).rounded())
            kMax = wholeCount(min(roomW / 16, bounds.height / 9).rounded(.down))
        } else {
            rawK = wholeCount(((rect.height + dir.y * delta.dy) / 9).rounded())
            kMax = wholeCount(min(roomH / 9, bounds.width / 16).rounded(.down))
        }
        let k = limitedK(rawK, upTo: kMax)
        let width = CGFloat(16 * k)
        let height = CGFloat(9 * k)

        let x: CGFloat
        if dir.x > 0 { x = rect.minX }
        else if dir.x < 0 { x = rect.maxX - width }
        else { x = (rect.midX - width / 2).rounded(.down) }

        let y: CGFloat
        if dir.y > 0 { y = rect.minY }
        else if dir.y < 0 { y = rect.maxY - height }
        else { y = (rect.midY - height / 2).rounded(.down) }

        return fitted(origin: CGPoint(x: x, y: y), k: k, in: bounds)
    }

    /// The largest 16:9 frame that fits `display`, centred vertically (rounded
    /// down) and placed at the left, centre or right.
    public static func preset(_ preset: RegionPreset, in display: CGRect) -> CGRect {
        let bounds = wholeBounds(of: display)
        let k = maxK(in: bounds)
        let width = CGFloat(16 * k)
        let height = CGFloat(9 * k)
        let x: CGFloat
        switch preset {
        case .left: x = bounds.minX
        case .center: x = bounds.minX + ((bounds.width - width) / 2).rounded(.down)
        case .right: x = bounds.maxX - width
        }
        let y = bounds.minY + ((bounds.height - height) / 2).rounded(.down)
        return fitted(origin: CGPoint(x: x, y: y), k: k, in: bounds)
    }

    /// Restores a rect stored relative to the display origin. Nothing stored,
    /// or an implausible stored rect (non-finite, empty, or not overlapping the
    /// display at all), gives the centre preset; any other stored rect is
    /// re-anchored at the display's current origin and clamped.
    public static func restore(local: CGRect?, in display: CGRect) -> CGRect {
        guard let local, isPlausible(local, onDisplayOfSize: display.size) else {
            return preset(.center, in: display)
        }
        return clamp(local.offsetBy(dx: display.minX, dy: display.minY), to: display)
    }

    // MARK: - Helpers

    /// Largest magnitude any input coordinate or delta may have. Far above any
    /// real display, far below where `Int` conversion or arithmetic misbehaves.
    private static let limit: CGFloat = 1e9

    /// `value` limited to `-limit...limit`; NaN becomes `fallback`.
    private static func bounded(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isNaN ? fallback : min(max(value, -limit), limit)
    }

    /// A whole number from an already-rounded value; never traps (NaN is 0,
    /// huge values saturate at `limit`).
    private static func wholeCount(_ value: CGFloat) -> Int {
        Int(bounded(value, fallback: 0))
    }

    /// `rect` with finite, bounded numbers: a NaN origin becomes the display's
    /// origin and a NaN size becomes zero (which the floor then lifts).
    private static func sanitized(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounded(rect.minX, fallback: bounds.minX),
            y: bounded(rect.minY, fallback: bounds.minY),
            width: bounded(rect.width, fallback: 0),
            height: bounded(rect.height, fallback: 0)
        )
    }

    /// A stored display-local rect is plausible when it is finite, has a
    /// positive size and overlaps the display. Huge but finite sizes are fine;
    /// `clamp` limits them.
    private static func isPlausible(_ local: CGRect, onDisplayOfSize size: CGSize) -> Bool {
        let values = [local.origin.x, local.origin.y, local.size.width, local.size.height]
        guard values.allSatisfy({ $0.isFinite }), local.size.width > 0, local.size.height > 0 else { return false }
        let overlap = local.intersection(CGRect(origin: .zero, size: size))
        return !overlap.isNull && overlap.width > 0 && overlap.height > 0
    }

    private static func direction(of handle: FrameHandle) -> (x: CGFloat, y: CGFloat) {
        switch handle {
        case .topLeft: (-1, 1)
        case .top: (0, 1)
        case .topRight: (1, 1)
        case .right: (1, 0)
        case .bottomRight: (1, -1)
        case .bottom: (0, -1)
        case .bottomLeft: (-1, -1)
        case .left: (-1, 0)
        }
    }

    /// `k` limited to `minK...kMax`; a display too small for `minK` wins over the floor.
    private static func limitedK(_ k: Int, upTo kMax: Int) -> Int {
        let hi = max(kMax, 1)
        let lo = min(minK, hi)
        return min(max(k, lo), hi)
    }

    /// The largest whole-number rect inside `display`.
    private static func wholeBounds(of display: CGRect) -> CGRect {
        let minX = display.minX.rounded(.up), minY = display.minY.rounded(.up)
        return CGRect(x: minX, y: minY, width: display.maxX.rounded(.down) - minX, height: display.maxY.rounded(.down) - minY)
    }

    /// A 16k x 9k rect at `origin`, shifted to lie inside `bounds`.
    private static func fitted(origin: CGPoint, k: Int, in bounds: CGRect) -> CGRect {
        let width = CGFloat(16 * k)
        let height = CGFloat(9 * k)
        let x = max(bounds.minX, min(origin.x, bounds.maxX - width))
        let y = max(bounds.minY, min(origin.y, bounds.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

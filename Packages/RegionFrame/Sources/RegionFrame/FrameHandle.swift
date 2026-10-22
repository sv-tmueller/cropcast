/// One of the eight resize handles of the frame. Edge names follow AppKit's
/// bottom-left origin: `top` is the edge at `maxY`.
enum FrameHandle: CaseIterable, Sendable, Hashable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

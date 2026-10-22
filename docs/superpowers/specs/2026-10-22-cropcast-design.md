# CropCast design

Date: 2026-10-22. Status: approved in refinement with the owner.

## Problem

The owner works on a 49" ultrawide (5120x1440). Sharing the whole screen in
Teams is too much; sharing one application is too little. They want to share
a chosen rectangle of the monitor, and pick it in the Teams share picker like
any other screen.

## Solution

A macOS menu bar app (no Dock icon) that:

1. Creates a virtual display named "CropCast" (2560x1440, 60 Hz, non-HiDPI)
   via the private `CGVirtualDisplay` API. Teams lists it as a screen.
2. Shows a frame overlay on the physical display. The frame is movable and
   resizable, locked to 16:9, with presets (left, center, right full-height
   16:9 slot) and remembers the last region.
3. Captures the region inside the frame with ScreenCaptureKit at 60 fps,
   cursor included, excluding CropCast's own windows (so the frame border is
   never shared), and renders it full-screen on the virtual display.
4. Region moves and resizes apply live, without restarting the stream.
5. Is controlled from the menu bar (start/stop, show/hide frame, presets,
   quit) and a global hotkey that toggles the frame.

Alternatives considered and rejected: DeskPad-style "virtual desk" (does not
share a region of the physical screen), monitor PBP mode (loses the seamless
ultrawide), free aspect ratio (resize would recreate the display and make
viewers' layout jump).

## Constraints

- Personal use. Private API accepted; no App Store, no notarization.
- macOS 26 (Apple Silicon). Minimum deployment target macOS 14.
- Toolchain: Swift 6 + Command Line Tools only (no Xcode). Build with SwiftPM;
  a script assembles the `.app` bundle. `swift test` with Swift Testing
  needs the CLT framework paths; use `scripts/swift-test.sh <package-dir>`.
- Screen Recording permission (TCC) is bound to the code signature. The
  bundle script signs with a stable identity when one is configured so the
  grant survives rebuilds; ad-hoc signing is the fallback.

## Module layout

Independent local SwiftPM packages, integrated by the app target:

| Module | Path | Responsibility |
|---|---|---|
| App shell | `/` (root package, `CropCast` executable) | Menu bar, hotkey, bundling, signing, later: wiring |
| VirtualDisplay | `Packages/VirtualDisplay` | Create/destroy the virtual display, place it in the arrangement |
| RegionMirror | `Packages/RegionMirror` | Capture a rect of a display, render frames on a target display |
| RegionFrame | `Packages/RegionFrame` | Frame overlay UI, 16:9 geometry, presets, persistence |

Modules do not depend on each other. Only the app target imports them.
Each module ships a small demo executable for manual verification, and unit
tests for its pure logic (geometry, placement, coordinate conversion).

## Risks

- `CGVirtualDisplay` is private and may change in a macOS update. Isolated
  behind the VirtualDisplay module so a breakage stays local.
- The cursor can wander onto the virtual display. Mitigation: place it so it
  touches the main display only at a corner.
- Coordinate systems: AppKit (bottom-left origin, points) versus
  CoreGraphics/ScreenCaptureKit (top-left origin, display-local). Conversion
  is a pure function with unit tests.

## Batching

- Batch 1: the four modules above, built in parallel.
- Batch 2: integration (session start/stop, live region updates, permission
  onboarding, sleep and display-change handling, usage README, manual Teams
  test checklist).

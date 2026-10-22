# Architecture overview

CropCast is a macOS menu bar app that mirrors a 16:9 region of a physical
display onto a virtual display, so the region can be picked as a "screen" in
Teams (or any screen-sharing tool). Full design:
`docs/superpowers/specs/2026-10-22-cropcast-design.md`.

## Rules

1. Modules under `Packages/` are independent SwiftPM packages. They never
   import each other; only the root `CropCast` app target composes them.
2. Private API use (`CGVirtualDisplay`) lives only in `Packages/VirtualDisplay`.
3. Pure logic (geometry, coordinate conversion, placement) is separated from
   AppKit/ScreenCaptureKit glue and covered by Swift Testing unit tests.
4. CropCast's own windows are always excluded from capture.
5. No Xcode dependency: SwiftPM plus scripts. Run tests with
   `scripts/swift-test.sh <package-dir>`.

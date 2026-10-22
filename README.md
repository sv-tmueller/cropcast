# CropCast

Share a 16:9 region of an ultrawide monitor as its own "screen" in Teams (or any
screen-sharing tool). CropCast creates a virtual display and mirrors the region
inside a movable frame onto it.

Status: in development. Design: `docs/superpowers/specs/2026-10-22-cropcast-design.md`.

## Requirements

- macOS 14+ (developed on macOS 26, Apple Silicon)
- Swift 6 toolchain (Command Line Tools are enough, no Xcode needed)

## Tests

    scripts/swift-test.sh <package-dir>

# CropCast

macOS menu bar app that mirrors a 16:9 region of a physical display onto a
virtual display so it can be shared as a "screen" in Teams. Read
`docs/architecture/overview.md` and
`docs/superpowers/specs/2026-10-22-cropcast-design.md` before working.

## Useful commands

- Install: N/A (no third-party dependencies; SwiftPM only)
- Build a package: `swift build --package-path <package-dir>`
- Test a package: `scripts/swift-test.sh <package-dir>` (root package: `scripts/swift-test.sh .`)
- Build the app bundle (once the root package exists): `make app`

Toolchain: Swift 6 with Command Line Tools only. There is no Xcode, so no
`xcodebuild` and no XCTest. Use Swift Testing (`import Testing`), and always
run tests through `scripts/swift-test.sh`. Plain `swift test` cannot find
the framework.

## Conventions

- Each module under `Packages/<Name>` is its own SwiftPM package
  (`swift-tools-version: 6.0`, `platforms: [.macOS(.v14)]`, Swift 6 language
  mode). Modules never import each other.
- Keep pure logic (geometry, coordinate conversion, placement) in plain
  functions/structs with unit tests. Keep AppKit/ScreenCaptureKit glue thin.
- Each module has a `README.md` with a manual verification checklist for what
  unit tests cannot cover (GUI, permissions, Teams).
- Conventional commits. One package = one branch = one PR with `Closes #N`.
- Do not edit another package's directory or the root `README.md` in a module PR.

## Sizing

size:S < 1h, size:M 1-3h (sub-plan first), size:L/XL must be split.

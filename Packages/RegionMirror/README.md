# RegionMirror

Captures a rectangle of one display with ScreenCaptureKit and renders it
full-screen on another display. Part of CropCast; independent of the other
packages.

## API

- `RegionGeometry.captureSourceRect(forAppKitRegion:displayFrame:)`: pure
  AppKit-to-ScreenCaptureKit rect conversion (unit tested).
- `CaptureSettings`: output size, fps, cursor. `makeConfiguration(sourceRect:)`
  builds the complete `SCStreamConfiguration` (default 2560x1440 at 60 fps).
- `RegionCapture`: `start(region:renderer:)`, `updateRegion(_:)`,
  `excludeWindows(_:)`, `stop()`, `onStop`, `deliveredFrameCount`. Regions are
  AppKit global coordinates (points, bottom-left origin). The whole app is
  excluded from capture (`excludingApplications`), so windows created later are
  hidden too; extra windows of other apps go through `excludeWindows(_:)`
  (`exceptingWindows`). Listing own windows one by one is only a fallback when
  the app is missing from the shareable content.
  Lifecycle: start and stop are serialized (pure `CaptureLifecycle`, unit
  tested). `start` on a starting or running capture throws `.alreadyRunning`
  (it never restarts). `stop()` during a start cancels it: the start stops its
  own stream and throws `.notRunning`. `.notRunning` from `start()` means
  exactly that `stop()` was called before the start resolved (it wins even if
  an await also failed); otherwise a stream that ended during the start throws
  its own error. `updateRegion` and `excludeWindows`
  during a start are stored and applied before `start` returns.
- `MirrorView` / `MirrorWindow`: `AVSampleBufferDisplayLayer`-backed view and a
  borderless full-screen window on a target display.
- `RegionMirrorError`: the only error type thrown. `-3801` maps to
  `.permissionDenied`; `.alreadyRunning` is a second `start`.

The module never requests Screen Recording permission. It checks it and throws
`.permissionDenied`; requesting it is the app's job (batch 2).

## Tests

```
scripts/swift-test.sh Packages/RegionMirror
```

## Demo

```
swift run --package-path Packages/RegionMirror regionmirror-demo [--target <displayID>] [--source <displayID>] [--seconds N] [--request-permission]
```

By default it mirrors a 16:9 region (half the display width) of the main
display into a 960x540 window, and every 2 s moves the region sideways by 25%
of the display width. It logs frames per second and the latency of each
`updateRegion` once per second. `--target` renders full-screen on that display
instead (for example the ultrawide, or a display made by `vdisplay-demo`).
`--request-permission` triggers the system prompt; automated runs must not use
it.

## Manual verification checklist

Needs a terminal app that has Screen Recording permission. On macOS 15 and
later the grant may need to be confirmed again in System Settings > Privacy &
Security > Screen & System Audio Recording after a few days or a reboot.

- [ ] Without permission: `regionmirror-demo --seconds 5` prints which app to
      grant, exits with status 1, opens no window and does not hang.
- [ ] With permission: the window shows the live region, smooth at about 60 fps,
      with the cursor visible.
- [ ] Every 2 s the region shifts and the mirror follows without a black flash.
- [ ] The demo window never appears inside the mirror (no mirror-in-mirror),
      even where it overlaps the captured region.
- [ ] `--target <id>` shows the mirror full-screen on that display, aspect
      filled, covering the menu bar and Dock, and the capture of that display
      itself does not show it.

## Deferred to batch 2

- Combining rapid `updateRegion` calls during a drag.
- Moving the region to another display.
- Sleep and display-change handling.

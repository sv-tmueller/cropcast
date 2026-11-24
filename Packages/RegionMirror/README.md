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
  tested). `start` on a starting or running capture throws `.alreadyRunning` (it
  never restarts). `stop()` during a start cancels it: the start stops its own
  stream and throws `.notRunning`. `.notRunning` from `start()` means exactly
  that `stop()` was called before the start resolved (it wins even if an await
  also failed); otherwise a stream that ended during the start throws its own
  error. `updateRegion` and `excludeWindows` during a start are stored and
  applied before `start` returns.
- Logging: while a capture runs, the module logs the frame flow with
  `os.Logger` (subsystem `com.github.sv-tmueller.cropcast`, category
  `capture`), so a frozen share names the failing layer. Logging only: no
  recovery, no public API. See "Diagnosing a freeze". The classification is
  pure (`FrameFlow.swift`, unit tested); the timer and logger are in
  `FrameFlowWatchdog.swift`.
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
swift run --package-path Packages/RegionMirror regionmirror-demo [--target <displayID>] [--source <displayID>] [--seconds N] [--static] [--request-permission]
```

By default it mirrors a 16:9 region (half the display width) of the main
display into a 960x540 window, and every 2 s moves the region sideways by 25%
of the display width. It logs frames per second and the latency of each
`updateRegion` once per second. `--target` renders full-screen on that display
instead (for example the ultrawide, or a display made by `vdisplay-demo`).
`--static` starts at the right-hand region position (away from the demo
window) and never moves the region, so the captured content stays still.
`--request-permission` triggers the system prompt; automated runs must not use
it.

## Diagnosing a freeze

If a shared screen freezes, note the time and read the capture log afterwards:

```
log show --last 1d --predicate 'subsystem == "com.github.sv-tmueller.cropcast" AND category == "capture"'
```

Live, while reproducing:

```
log stream --predicate 'subsystem == "com.github.sv-tmueller.cropcast" AND category == "capture"'
```

A watchdog timer (its own queue, every 2 s, independent of frames arriving)
compares the counters of each window and logs a line only when the state
changes, plus one heartbeat about every 60 s (30 ticks, so the first one comes
at about 60 s).

### Log lines

| Line | Level | Content |
|---|---|---|
| `capture started` | notice | display ID, source rect, output size, fps |
| `capture stopped by request` | notice | cumulative counters |
| `stream ended by itself` | error | error domain, code, description, cumulative counters |
| `frame flow <old> -> <new>` | error unless the new state is `healthy` (and `silent`, see below) | how long the old state lasted, the window's counters, renderer snapshot |
| `heartbeat` | notice | current state, cumulative counters, renderer snapshot |
| `renderer flushed after failed` | notice, at most once per window | flush count in the window, the renderer error from just before the flush |

Counters: `received` (every `.screen` callback), `complete` / `idle` / `other`
(by `SCFrameStatus`; `other` is blank, suspended, started, stopped or
unreadable), `enqueued` (handed to the renderer), `droppedNotReady` (complete
frames skipped because the renderer was not ready), `flushes` (flushes after
`.failed`). Renderer snapshot: `status`, `error`, `ready`
(`isReadyForMoreMediaData`), `requiresFlush` (`requiresFlushToResumeDecoding`).

### States

| State | Window condition | Points at |
|---|---|---|
| `callbackStuck` | a frame callback has been running longer than the window | the callback hangs inside renderer `enqueue` or `flush`. The renderer is not read then: the line says `renderer: not read (callback in flight)` |
| `silent` | no callbacks at all | with no `stream ended by itself` line: ScreenCaptureKit stopped delivering without ending the stream (candidate 1). Caveat: a static region may legitimately deliver nothing, see below |
| `rendererBlocked` | complete frames arrived, none were enqueued | the renderer refuses frames (candidate 2). Check `failed` and `requiresFlush` in the snapshot |
| `healthy` | anything else | with `enqueued` rising throughout: CropCast kept mirroring, so look at Teams (candidate 3) |

`healthy` does not always mean CropCast is mirroring. With `enqueued` flat and
`other` rising, ScreenCaptureKit is sending only blank or suspended statuses,
for example on a locked screen; that is still candidate 1. Rising `idle` means
the content is static. The cumulative counters in the heartbeat show which.

### `silent` and static content

It is not yet measured whether ScreenCaptureKit keeps delivering `idle`
callbacks while the captured region is static. Until it is measured, `silent`
ships as a fault: transitions into it are logged at error level
(`FrameFlowMonitor.silentIsFaultDefault = true`). If a static region delivers
no callbacks, a normal session logs `healthy`/`silent` changes, the constant
flips to `false` (those changes drop to notice level) and `silent` only points
at candidate 1 if the region was changing at the time of the freeze. The
result of owner check 3 below decides this.

### Notes

- Every interpolated value is logged `privacy: .public`; only counters,
  states, display IDs, rects and system error text are logged.
- Only the notice and error levels are used: `info` and `debug` are not kept
  on disk, and this log is read hours later.
- Durations use a clock that does not count system sleep, so a sleep never
  looks like `callbackStuck`. Durations in the log leave out sleep time; the log
  timestamps show wall time.
- Nothing is logged after the stop line.

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

Frame-flow log (read with `log stream` as above while the demo runs):

- [ ] With the demo running, the log shows the start line, a heartbeat within
      about 60 s with rising `enqueued`, and the stop line (`--seconds 70` ends
      in `stop()`). No value shows as `<private>`.
- [ ] A session with moving content logs only the start line, heartbeats and
      the stop line.
- [ ] `--static` for at least 10 s, with the cursor and the terminal outside
      the region: record whether it goes `silent`. Then apply the result (see
      "`silent` and static content").
- [ ] Lock the screen with the demo running: record what the log shows (a
      state change, a stream-ended line, or nothing).
- [ ] Run `pmset displaysleepnow` with the demo running: record the same.

## Deferred to batch 2

- Combining rapid `updateRegion` calls during a drag.
- Moving the region to another display.
- Sleep and display-change handling.

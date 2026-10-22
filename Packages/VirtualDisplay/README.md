# VirtualDisplay

Creates and removes a virtual display named "CropCast" (2560x1440, 60 Hz,
non-HiDPI) with the private `CGVirtualDisplay` API, so screen-sharing tools such
as Teams list it as a screen. It also places the display in the arrangement so
it touches the main display only at its bottom-left corner.

Standalone SwiftPM package. No dependency on other CropCast modules.

## API

```swift
let display = try await VirtualDisplay.start()   // throws VirtualDisplayError
display.displayID                                // CGDirectDisplayID
display.stop()                                   // safe to call twice; also on deinit
```

`start()` is all-or-nothing: it creates the display, waits (up to about 2 s)
until it shows up in `CGGetActiveDisplayList`, then moves it into place. On any
failure nothing is left behind.

`VirtualDisplayError`: `apiUnavailable(String)`, `creationFailed(String)`,
`settingsRejected`, `didNotComeOnline`, `placementFailed(CGError)`.

**Requires the AppKit event loop.** The process must run `NSApplication.run()`
(any real app does) while a display exists. Under Swift's async main
(top-level `await`) or a bare `CFRunLoopRun()`, CoreGraphics stops refreshing
this process's display list after the placement transaction. `stop()` still
removes the display system-wide (other processes and `system_profiler` see it
gone within about a second), but `CGGetActiveDisplayList` in the calling
process keeps listing it until exit, and the next `start()` throws
`.didNotComeOnline`. This was the cause of the "display stays after `stop()`"
bug (issue #3 test round 2): the display itself was removed, the process's own
view of it was stale. It showed up for display identities the OS had not seen
before and for a second start in the same process; `vdisplay-demo` now runs
`NSApplication.run()` and passes `--cycles 5` with new and remembered serials.

Not handled here: the private `terminationHandler`, sleep/wake and display
reconfiguration. The integration batch owns that.

## Design notes

- All private-API use is in one file, `Sources/CVirtualDisplayShim/CVirtualDisplayShim.m`.
  The classes are looked up with `NSClassFromString` and every selector is
  checked first, so nothing links against the private classes. If a future macOS
  removes them, `start()` throws `.apiUnavailable` instead of the app failing to
  launch with "Symbol not found". Objective-C exceptions are caught there too.
- The private `@interface` declarations are in `CGVirtualDisplayPrivate.h`,
  deliberately outside `include/`, so Swift never sees them.
- Placement (`Placement.origin(mainBounds:displaySize:)`) is a pure function:
  `(main.minX - width, main.maxY)` in CoreGraphics global coordinates, i.e.
  (-2560, 1440) next to a 5120x1440 main display. The top corners are avoided
  because users aim for the menu bar there, and the bottom-right is the default
  Quick Note hot corner.
- The display uses a fixed vendor/product/serial so macOS does not remember a
  new display on every run.

## Commands

```sh
swift build --package-path Packages/VirtualDisplay
scripts/swift-test.sh Packages/VirtualDisplay
swift run --package-path Packages/VirtualDisplay vdisplay-demo --seconds 30
# start/stop 5 times in one process; exit 1 if any stop leaves the display
swift run --package-path Packages/VirtualDisplay vdisplay-demo --cycles 5 --seconds 1
# D1 check: must print nothing (no direct link to the private classes)
nm -um Packages/VirtualDisplay/.build/debug/vdisplay-demo | grep 'OBJC_CLASS_\$_CGVirtualDisplay'
```

Unit tests never create a real display (the failure-path tests inject bogus
class names). The demo is the real-path check: it logs the active display count
before, during and after, plus the requested and actual placement, and exits 0
only if the count went N -> N+1 -> N. With `--cycles N` it repeats start/stop N
times in one process (polling up to 5 s after each stop) and exits 1 if any
cycle fails. Option parsing and the pass/fail rule live in the internal
`VirtualDisplayDemoSupport` target and are unit-tested.

## Manual verification checklist

Run from a GUI terminal session, not over SSH.

- [ ] `vdisplay-demo --seconds 30` exits 0 and logs `N -> N+1 -> N` display counts.
- [ ] `vdisplay-demo --cycles 5 --seconds 1` exits 0 (`5/5 cycles passed`); run it a few times.
- [ ] While it runs, System Settings > Displays lists "CropCast" (2560x1440).
- [ ] The arrangement shows CropCast touching the main display only at its
      bottom-left corner. If macOS adjusted the position, the demo log shows
      requested vs actual bounds; note what macOS did.
- [ ] While it runs, the Teams share picker lists one more screen (it may be
      named "Screen N" rather than "CropCast").
- [ ] After the demo exits, the display is gone from System Settings > Displays.
- [ ] Ctrl-C during the run also removes the display.

The earlier "first run leaves the display in place" flake is most likely
the event-loop problem above (a new display identity made the process's display
list go stale); it has not recurred since the demo runs `NSApplication.run()`.

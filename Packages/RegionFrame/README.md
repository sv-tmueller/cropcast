# RegionFrame

The movable, resizable 16:9 frame overlay that marks the region CropCast mirrors.
Pure geometry, border layout and persistence are unit tested; the AppKit panels
are verified by hand with the demo.

## Design

- **Click-through by construction.** The frame is four thin border panels
  (`NSPanel`, borderless, non-activating) placed *inside* the region rect. No
  window covers the interior, so clicks, scrolls and typing always reach the app
  below. Strips sit inside the rect (not outside) because presets touch the
  display edges.
- **Exactly 16:9** means `w = 16k`, `h = 9k` with `k` a whole number of points,
  so `w*9 == h*16`. Minimum 640x360 (`k = 40`); maximum is the largest that fits.
- **Handles.** Corners are L-shaped brackets, edges have a bar at their midpoint,
  the rest of the band moves the frame. Resizing a corner keeps the opposite
  corner fixed; resizing an edge keeps the opposite edge fixed and re-centres
  the other dimension (shifted, never shrunk, to stay inside).
- **Clamped to the display** (`NSScreen.frame`, not `visibleFrame`, so a
  2560x1440 slot fits under the menu bar). Dragging never crosses displays; use
  `show(on:)` or `apply(preset:on:)` to change display.
- **Presets** (`RegionPreset`): `.left`, `.center`, `.right` are the largest
  16:9 frame that fits, centred vertically.

## API

```swift
let overlay = FrameOverlay(defaults: .standard)   // the app passes .standard
overlay.regionDidChange = { region in /* FrameRegion(displayID:rect:) */ }
overlay.show(on: displayID)
overlay.apply(preset: .right, on: displayID)
overlay.hide()
overlay.windowNumbers   // 4 panel window numbers, stable across show/hide
```

`FrameRegion.rect` is in AppKit global coordinates (bottom-left origin, points).
`regionDidChange` fires on first placement, on every drag step that changes the
rect and on each preset; identical regions are skipped.

## Persistence

One versioned blob under `RegionFrame.state.v1` in the defaults you pass:
`{ lastDisplayKey, frames: [displayKey: rect measured from the display origin] }`.
The display key is the display UUID (fallback `cg-<vendor>-<model>-<serial>`).
Saved on mouse-up, on `apply(preset:)` and on `show(on:)`, never on every drag
step. Nothing stored, undecodable data, or an implausible stored rect (non-finite,
empty or not on the display) falls back to the centre preset; geometry never
traps on NaN, infinite or out-of-range numbers.

The module never hard-codes a bundle id. The demo uses its own suite and the
tests use a unique throwaway suite each; neither touches `UserDefaults.standard`.

## Run the demo

```sh
swift build --package-path Packages/RegionFrame
D=Packages/RegionFrame/.build/debug/regionframe-demo
$D --list                                  # displays: id and frames
$D --display 1 --preset right --seconds 5  # a display id from --list (id=, not a position)
$D --display 1 --cycle-presets --seconds 4 # left, center, right, once per second
$D --reset --display 1 --seconds 1         # forget saved regions first
$D                                         # run until Ctrl-C, drag by hand
```

Every region change prints the display id, global rect, local rect, and
`16:9=ok|FAIL` and `inside=ok|FAIL`. The demo saves into the suite
`com.github.sv-tmueller.cropcast.regionframe-demo`; clear it with:

```sh
defaults delete com.github.sv-tmueller.cropcast.regionframe-demo
```

## Manual verification checklist

Run `regionframe-demo` (no `--seconds`) and check, on every connected display:

- [ ] `--list` shows every display with its id; `--cycle-presets` prints left/centre/right
      with `16:9=ok inside=ok` (ultrawide 5120x1440: three 2560x1440 slots).
- [ ] Dragging the band moves the frame; it stops at all four display edges.
- [ ] All 8 handles (4 corner brackets, 4 edge bars) resize and keep exactly
      16:9, stay inside the display, and stop at 640x360.
- [ ] Clicks, scrolling and typing inside the frame reach the app below it.
- [ ] Clicking or dragging the border does not take focus from the front app
      (its title bar stays active).
- [ ] The frame stays visible across app switches and Spaces and sits above the
      menu bar (place a preset that touches the top of the display).
- [ ] After a drag by hand, Ctrl-C and relaunch with `--display <id>`: the frame
      reappears at the dragged region.
- [ ] `--reset` then relaunch: the frame is centred.
- [ ] The four `windowNumbers` printed at startup match the border windows
      (they are what batch 2 excludes from capture), and no demo process is
      left running afterwards.

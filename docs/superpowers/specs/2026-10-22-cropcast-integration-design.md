# CropCast integration design (batch 2)

Date: 2026-10-22. Status: approved in refinement with the owner.
Builds on `2026-10-22-cropcast-design.md` and the merged modules (#6-#9).

## Verified assumption

On the owner's Mac, while `vdisplay-demo` runs, Teams lists the CropCast
virtual screen in its Share picker.

## Behaviour

- **Start Sharing** (menu):
  1. Check Screen Recording permission. If it is missing, explain why it is
     needed, offer "Open System Settings", request access, and stop. Never
     leave a half-started session.
  2. Create the CropCast virtual display (VirtualDisplay).
  3. Open the full-screen mirror window on it (RegionMirror `MirrorWindow`).
  4. Show the frame (RegionFrame) on the source display, then start
     capturing the frame's region into the mirror.
  5. The menu reads "Stop Sharing".
  - Any failure tears down whatever was already started (all-or-nothing),
    and the error is reported in an alert.
- **Stop Sharing**: stop capture, close the mirror window, remove the
  virtual display, and hide the frame. Quitting the app does the same.
- **Region changes**: moving or resizing the frame, or picking a preset,
  updates the captured region live. Updates are coalesced: at most one
  `updateRegion` is in flight, and the latest rect wins.
- **Hotkey ⌃⌥⌘F**: shows or hides the frame at any time. Viewers never see
  the frame border, because capture excludes CropCast's own windows.
- **Presets** (menu Left/Center/Right): apply to the frame on its current
  display.
- **Source display**: the last used display if it is still connected, else
  the widest connected display. Never the CropCast virtual display.
- **Install**: `make install` builds, signs and copies CropCast.app to
  /Applications, replacing an older copy.

## Constraints carried over from batch 1

- VirtualDisplay needs `NSApplication.run()` for the whole process life.
  The app satisfies this.
- RegionMirror `start`/`stop` are not serialized yet. Batch 2 adds a
  start-in-progress state inside the module, with no public API change.
- Agents have no Screen Recording grant, so the live end-to-end checks are
  manual and done by the owner.

## Batching

- **Batch 2:** session wiring (app target), `make install`, RegionMirror
  start/stop serialization, the module nit sweep, and the usage README with
  a Teams checklist.
- **Batch 3:**
  - Sleep and wake.
  - Displays connecting or disconnecting, and display mode changes.
  - Teardown when the stream stops unexpectedly.
  - The launch-at-login toggle. It needs the batch-2 menu, which the
    session package owns.

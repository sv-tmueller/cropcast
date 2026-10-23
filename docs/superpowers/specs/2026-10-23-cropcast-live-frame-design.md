# CropCast live frame and launch at login fix (batch 4)

Date: 2026-10-23. Status: approved in refinement with the owner.
Builds on `2026-10-23-cropcast-settings-design.md`.

## Problems reported

- **Launch at login does nothing.** In the installed CropCast, signed with
  `CropCast Self-Signed`, clicking the switch leaves it off. CropCast does
  not appear in System Settings > General > Login Items (neither "Open at
  Login" nor "Allow in the Background"). CropCast logs nothing about it, so
  the failure is silent.
- **No visual difference while sharing.** The frame border is blue whether
  or not a share session is running. The owner wants a red border while
  sharing, like the red border Teams draws around a shared screen.

## Decisions

- **"Red" means the CropCast session is live.** The frame is red from
  Starting… through Sharing and Stopping…, and blue when idle (including
  after a failed start). macOS has no public API to tell whether Teams, or
  any other app, is capturing the CropCast virtual display, so CropCast
  cannot detect real broadcasting and does not try.
- **The menu bar icon also shows the live state** (a filled or tinted
  symbol), so the state is visible with the frame hidden.
- **One-time exception to "one package = one PR".** The border colors are
  private to `Packages/RegionFrame`. Batch 4 package 2 adds a small public
  "live" style switch to RegionFrame, with its tests and README, and wires
  it into the app in the same PR. The owner approved this exception for
  this change only. Modules still never import each other.
- **Launch at login must never fail silently.** Every status read,
  register/unregister attempt and error is logged to CropCast's own system
  log subsystem, and any failure appears as text under the switch.

## Batch 4 packages

1. Launch at login registers, or says why.
2. Red frame while the session is live, plus the menu bar indicator.
3. README checklist fixes left over from batch 3.

## Deferred to batch 5

Display picker and permission status in Settings; live display switch;
sleep/wake and display connect/disconnect handling; teardown and
notification when the stream stops by itself; `Logger` privacy.

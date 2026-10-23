# CropCast settings, Dock icon and display choice (batch 3)

Date: 2026-10-23. Status: approved in refinement with the owner.
Builds on `2026-10-22-cropcast-design.md` and
`2026-10-22-cropcast-integration-design.md`.

## Problems reported

- On the ultrawide, the frame stays on the built-in display. Start always
  reuses `CropCast.lastSourceDisplayKey`, and the frame cannot be dragged
  across displays, so there is no way to move it.
- Start Sharing asks for Screen Recording permission again although it was
  granted the night before. The installed app is signed ad-hoc (no
  `CropCast Self-Signed` certificate in the keychain), so every rebuild
  changes the signature and orphans the grant. Reinstalling cannot help.
- There is no window to configure the app, and no Dock icon.

## Decisions

- **Dock icon: a toggle, on by default.** This replaces "no Dock icon" in
  the original design. `LSUIElement` stays in `Info.plist`; the app sets its
  activation policy at launch from the setting, and the toggle applies it
  at runtime without a relaunch. With the Dock icon shown, the app has a
  minimal app menu (Settings…, Quit CropCast). Clicking the Dock icon opens
  Settings. The menu bar icon stays in both modes.
- **Settings window ("General").** Opened from the menu (Settings…, ⌘,),
  the Dock icon and the app menu. It holds Show in Dock and Launch at login
  (`SMAppService.mainApp`) in batch 3; the source display picker and the
  permission status row move into it in batch 4, once batch 3 is merged.
- **Source display choice: only while idle.** A Display submenu lists the
  connected physical displays (never the virtual one) with a checkmark on
  the current source. Choosing one moves the frame there and makes it the
  source of the next Start. It is disabled while starting, sharing or
  stopping. Live switching during a share is out of scope.
- **Stale grant recovery.** The permission alert offers "Reset & Grant
  Again", which resets only CropCast's own ScreenCapture entry and requests
  access again. `make signing-cert` creates the self-signed code-signing
  certificate so the grant survives rebuilds.

## Batch 3 packages

1. Settings window, Dock icon toggle and launch at login.
2. Source display choice from the menu.
3. Reset a stale Screen Recording grant from the permission alert.
4. `make signing-cert`.

## Deferred to batch 4

Display picker and permission status in Settings; live display switch;
sleep/wake and display connect/disconnect handling; teardown and
notification when the stream stops by itself; `Logger` privacy.

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

## Build and run

    make test    # unit tests (scripts/swift-test.sh .)
    make app     # build and sign build/CropCast.app
    make clean   # remove build/
    open build/CropCast.app

`swift run CropCast` also works for a quick check; it runs without a Dock icon
but is not a signed bundle, so use the `.app` for anything involving
permissions. The menu bar icon (dashed rectangle) offers Start/Stop Sharing,
Show/Hide Frame, a Presets submenu (Left, Center, Right) and Quit. The global
hotkey Control-Option-Command-F triggers the same action as Show/Hide Frame.
For how to share a region in Teams, see "Using CropCast with Teams" below.

## Stable code signing

macOS binds the Screen Recording permission to the app's code signature. An
ad-hoc signature changes on every build, so the grant is lost each time. To
keep it, sign with a stable certificate. Run once:

    make signing-cert

This creates `CropCast Self-Signed` (RSA 2048, valid 10 years) in your login
keychain and trusts it for code signing only. macOS asks once for your
password or Touch ID to change the trust setting; no sudo is needed. Running
it again changes nothing. If you cancelled the prompt, running it again only
asks for trust and does not create a second certificate. An expired or
ambiguous certificate is reported together with how to remove it; the script
never deletes keychain items itself.

Verify: `security find-identity -v -p codesigning` lists
`CropCast Self-Signed`.

Manual fallback (Keychain Access), if you prefer not to use the script:

1. Open Keychain Access, then Certificate Assistant, then Create a Certificate.
2. Name: `CropCast Self-Signed`. Identity Type: Self Signed Root.
   Certificate Type: Code Signing. Create it.
3. Open the certificate, expand Trust and set Code Signing to Always Trust.
4. Verify: `security find-identity -v -p codesigning` lists
   `CropCast Self-Signed`.

`make app` picks this certificate up automatically. To use another identity,
set `CROPCAST_SIGN_IDENTITY` (a certificate name or SHA-1, or `-` for ad-hoc);
the build fails if signing with it fails. Without any identity the script signs
ad-hoc and prints a warning.

After changing the signing identity, reset the stale grant:

    tccutil reset ScreenCapture com.github.sv-tmueller.cropcast

Manual verification (`make signing-cert`):

- [ ] `make signing-cert`, then Cancel at the trust dialog: exits nonzero with
      a retry hint; `security find-identity -p codesigning` shows one
      `CSSMERR_TP_NOT_TRUSTED` entry.
- [ ] `make signing-cert` again: only the trust dialog appears, no second
      certificate; approve it. Exits 0 and prints the SHA-1, and
      `security find-identity -v -p codesigning` lists `CropCast Self-Signed`.
- [ ] `make signing-cert` a third time: prints "already set up", exits 0, no
      dialog. Keychain Access (login, search "CropCast") shows one certificate
      and one key.
- [ ] `make app`: reports signing with `CropCast Self-Signed`, shows no
      "codesign wants to access key" dialog, and `codesign --verify --strict
      build/CropCast.app` exits 0. `codesign -dv build/CropCast.app 2>&1` shows
      `Authority=CropCast Self-Signed` and no `Signature=adhoc`.
- [ ] `make install`: prints no ad-hoc note (this checks that the note stays
      silent on a signed build). Reset the grant once, `make install` again:
      Start Sharing works without the permission alert.
- [ ] `ls -d "$TMPDIR"/cropcast-cert.*` matches nothing.

## Using CropCast with Teams

### Install

    make install      # build, sign, copy CropCast.app to /Applications
    make uninstall    # remove it again

`make install` replaces an older copy and quits a running CropCast only if it
runs from the bundle being replaced. Set `CROPCAST_INSTALL_DIR` to install
somewhere else (default `/Applications`); the directory must already exist and
be writable, and neither command uses `sudo`:

    CROPCAST_INSTALL_DIR="$HOME/Applications" make install

`make uninstall` only looks in `CROPCAST_INSTALL_DIR` (default
`/Applications`), so a copy installed into a custom directory needs the same
variable to be removed:

    CROPCAST_INSTALL_DIR="$HOME/Applications" make uninstall

The install ends with an `open "<path>"` line to launch the app. `make
uninstall` on a machine without CropCast reports "not installed" and succeeds.
If the build was signed ad-hoc, `make install` prints a Screen Recording
re-grant note; see "Screen Recording permission" below.

### Screen Recording permission

CropCast copies a region of your screen onto a virtual display, and macOS only
allows that after you grant Screen Recording access. The first time you choose
Start Sharing without it, CropCast shows "CropCast needs Screen Recording
permission" and starts nothing. The alert has three buttons:

- **Open System Settings** requests access and opens the Screen Recording pane.
  Switch CropCast on under Privacy & Security > Screen & System Audio
  Recording, then reopen CropCast and choose Start Sharing again.
- **Reset & Grant Again** is for a stale grant: System Settings already shows
  CropCast switched on, but Start still shows the alert (typical after an
  ad-hoc rebuild). It runs `tccutil reset ScreenCapture` for CropCast's bundle
  identifier, then requests access and opens the pane. Switch CropCast on, then
  Quit & Reopen when macOS offers it, and choose Start Sharing again. If the
  reset fails (for example when CropCast runs unbundled), an alert "Could not
  reset Screen Recording permission" gives the cause and the manual command,
  and nothing else happens.
- **Cancel** does nothing.

macOS ties the grant to the app's code signature. An ad-hoc signature changes
on every build, so the grant is lost after each rebuild or reinstall. To keep
it, sign with a stable certificate (see "Stable code signing" above). After a
re-sign or an ad-hoc build, choose Reset & Grant Again in the alert, or reset
the stale grant by hand and grant it again:

    tccutil reset ScreenCapture com.github.sv-tmueller.cropcast

### Sharing a region

1. Open CropCast (menu bar icon, no Dock icon) and choose **Start Sharing**.
   The item reads "Starting…" while the session comes up, then "Stop Sharing".
   Start creates the CropCast virtual display, opens a full-screen mirror of
   the region on it, shows the frame on your source display and starts
   capturing the frame's region. If any step fails, everything already started
   is undone and an alert "Sharing did not start" names the step.
2. The source display is the display the frame was last on if it is still
   connected, else the widest connected display. It is never the CropCast
   virtual display.
3. Position the frame over what you want to share. Dragging or resizing it, or
   choosing Presets > Left, Center or Right (applied to the frame on its
   current display), updates the shared region live. Viewers never see the
   frame border, because capture excludes CropCast's own windows.
4. The hotkey Control-Option-Command-F shows or hides the frame at any time,
   like Show Frame / Hide Frame in the menu.
5. In Teams, open the Share picker and choose the CropCast screen. It is a
   screen entry and may be listed as "Screen N".
6. When done, choose **Stop Sharing** ("Stopping…" while it winds down). Stop
   ends the capture, closes the mirror, removes the virtual display and hides
   the frame. Quitting CropCast does the same.

### Troubleshooting

- **No permission:** the alert appears on every Start until Screen Recording
  is granted. Grant it in System Settings, reopen CropCast and start again. If
  it was working before a rebuild or reinstall, the signature changed; choose
  Reset & Grant Again in the alert (or run the `tccutil reset` command above),
  or sign with a stable certificate.
- **The screen is not listed in Teams:** the CropCast screen exists only
  during a session, so look for it once the menu reads "Stop Sharing". Wait
  out "Starting…", check that no "Sharing did not start" alert appeared, then
  reopen Teams' Share picker. The entry may be named "Screen N", so do not
  look only for "CropCast".
- **The share is black or stops updating:** check that the permission is
  granted for the current signature (see "No permission"). If Screen Recording
  is revoked while sharing, the capture stops but the menu still says "Stop
  Sharing"; reacting to that is not handled yet. Choose Stop Sharing, fix the
  permission and start again.
- **The frame is on the wrong display:** choosing the display is not supported
  yet. Start keeps the display the frame was last on while it is connected, so
  Stop Sharing and Start Sharing again does not move it. To reset it, quit
  CropCast, run

      defaults delete com.github.sv-tmueller.cropcast \
          CropCast.lastSourceDisplayKey

  and reopen CropCast. Start then falls back to the widest connected display.
- **Not handled yet:** sleep/wake and a display connecting, disconnecting or
  changing mode. If a session misbehaves after one of these, choose Stop
  Sharing and start again.
- **Missing feature:** launch at login. CropCast does not start by itself, so
  open it after logging in.

### Teams test checklist

- [ ] `make install` puts CropCast.app in place and
      `open /Applications/CropCast.app` launches it (menu bar icon, no Dock
      icon).
- [ ] Start Sharing without Screen Recording permission shows the permission
      alert and starts nothing; "Open System Settings" opens the Screen
      Recording pane.
- [ ] With a stale grant (Settings shows CropCast on, Start still shows the
      alert), "Reset & Grant Again" shows the macOS prompt and opens the pane
      with CropCast off; after switching it on and reopening CropCast, Start
      Sharing works without Terminal. "Cancel" does nothing.
- [ ] After granting and reopening CropCast, Start Sharing reads "Starting…",
      then "Stop Sharing", and the frame appears on the source display.
- [ ] Teams' Share picker lists the CropCast screen (possibly "Screen N");
      sharing it shows the framed region live, including the cursor.
- [ ] Dragging and resizing the frame, and the Left, Center and Right presets,
      change what Teams shows; the frame border is not visible to viewers.
- [ ] Control-Option-Command-F hides and shows the frame.
- [ ] Stop Sharing ("Stopping…", then "Start Sharing") ends the share, and the
      CropCast screen disappears from the picker.
- [ ] Start again, then Quit while sharing; the virtual display is gone
      afterwards: `system_profiler SPDisplaysDataType | grep -c CropCast`
      prints 0.
- [ ] `make uninstall` removes the app; a second run prints "not installed".

## Manual verification (app shell)

- [ ] `make app` succeeds; `codesign -dv build/CropCast.app` shows
      `Identifier=com.github.sv-tmueller.cropcast`.
- [ ] `codesign --verify --strict build/CropCast.app` exits 0.
- [ ] `open build/CropCast.app`: an icon appears in the menu bar and there is
      no Dock icon and no app window.
- [ ] After `make install`, Finder shows the CropCast icon (not the generic app
      icon) for `/Applications/CropCast.app`; if stale, `touch` the app and
      `killall Finder`.
- [ ] Opening the menu shows Start Sharing, Show Frame, Presets (Left, Center,
      Right) and Quit CropCast.
- [ ] Pressing Control-Option-Command-F changes the menu label between
      Show Frame and Hide Frame (check by reopening the menu).
- [ ] Clicking Show Frame / Start Sharing flips the label on next open.
- [ ] Quit CropCast (or Command-Q with the menu open) terminates the app.

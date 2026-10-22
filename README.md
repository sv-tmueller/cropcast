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
Sharing, frame and presets are placeholders until the modules are wired in.

## Stable code signing

macOS binds the Screen Recording permission to the app's code signature. An
ad-hoc signature changes on every build, so the grant is lost each time. To
keep it, sign with a stable certificate:

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

## Manual verification (app shell)

- [ ] `make app` succeeds; `codesign -dv build/CropCast.app` shows
      `Identifier=com.github.sv-tmueller.cropcast`.
- [ ] `codesign --verify --strict build/CropCast.app` exits 0.
- [ ] `open build/CropCast.app`: an icon appears in the menu bar and there is
      no Dock icon and no app window.
- [ ] Opening the menu shows Start Sharing, Show Frame, Presets (Left, Center,
      Right) and Quit CropCast.
- [ ] Pressing Control-Option-Command-F changes the menu label between
      Show Frame and Hide Frame (check by reopening the menu).
- [ ] Clicking Show Frame / Start Sharing flips the label on next open.
- [ ] Quit CropCast (or Command-Q with the menu open) terminates the app.

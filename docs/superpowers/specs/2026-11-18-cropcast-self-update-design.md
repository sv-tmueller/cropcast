# CropCast self-update

Date: 2026-11-18. Status: approved by the owner. The assumptions in
"Unverified assumptions: test first" are not tested yet; nothing else is
built until they are.
Builds on `2026-10-22-cropcast-design.md` and
`2026-10-23-cropcast-settings-design.md`.

## Intent

CropCast is now used on more than the owner's Mac. Today the only way to
install or update it is to clone the repository and run `make install`,
which needs Command Line Tools and a terminal. The owner wants:

- **First install without cloning.** A person downloads CropCast from the
  GitHub release page, opens it and grants Screen Recording once.
- **Updates from inside the app.** CropCast asks GitHub whether a newer
  release exists. If so it says so, and on one click it downloads the new
  version, replaces itself and restarts. The Screen Recording permission
  stays.
- **No per-release chore for the owner.** Publishing a version must not
  need a command on the owner's Mac.
- A downloaded install and one built from a clone behave the same.

## Goals

- A release is published by creating a version tag; GitHub builds, signs
  and attaches the app.
- The installed app finds a newer release by itself and offers it.
- One click installs it and relaunches, with the permission, the settings
  and the login item intact.
- The app installs only updates that carry the same signature as itself.

## Non-goals

- Apple Developer ID, notarization, the App Store.
- Third-party code (no Sparkle).
- Installing without a click, or in the background.
- Delta updates, release channels, pre-releases, downgrades.
- Intel Macs. Releases are Apple Silicon only, like the app today.
- Release notes inside the app (a link to the release page is enough).

## Anti-goals

These would make the feature a failure even if it works:

- An update that makes macOS ask for Screen Recording again.
- Installing anything that is not signed with CropCast's certificate.
- Interrupting a running share to install.
- A failed update that leaves no working app in place.
- Sending anything about the user to GitHub beyond the request itself.

## Constraints

- macOS ties the Screen Recording grant to the code signature. Every
  release must therefore be signed with the same certificate.
- There is no Apple developer account, so the certificate is self-signed.
- Swift 6, Command Line Tools only, SwiftPM only, Swift Testing through
  `scripts/swift-test.sh`. Modules under `Packages/` never import each
  other.
- The repository is public, so releases can be read without a login.
- Agents have no Screen Recording grant and no second Mac. Everything that
  touches the grant, Gatekeeper or a real install is checked by the owner.

## Approaches

Three ways to give an updated app a signature that keeps the grant:

1. **One certificate, releases signed on GitHub (chosen).** The
   certificate's private key is a repository secret. A workflow builds,
   signs and publishes on a version tag. Every Mac gets the identical app,
   and the app can check a download's signature against its own before
   installing. Cost: the key lives on GitHub, so whoever controls the
   repository can publish an update the installed apps accept.
2. **One certificate, releases signed on the owner's Mac.** Same as 1, but
   the key never leaves the owner's Mac, so a taken-over repository cannot
   publish an accepted update. Cost: one command on the owner's Mac per
   release. Rejected by the owner for that reason.
3. **Unsigned release, re-signed on each Mac** with a per-Mac certificate
   that the updater creates if needed. No key on GitHub, but a download
   can only be checked against a checksum that comes from the same release,
   and the updater must create certificates and sign on Macs nobody can
   debug. Rejected: weaker check, more fragile.

Unsigned releases with a re-grant after every update were dropped at once:
they defeat the point of one click.

**Accepted consequence of 1:** if the certificate is lost or has to be
replaced, the installed apps refuse the next update. Each person then
downloads the new version by hand once and grants Screen Recording once.
A backup of the certificate in the owner's password manager prevents the
loss case.

## Decisions

Marked **(owner)** where the owner decided, **(call)** where this document
made the choice and the owner can overrule it.

### Signing

- **(owner)** Releases are signed on GitHub with one shared certificate.
- **(call)** The shared certificate is the owner's existing
  `CropCast Self-Signed` certificate, exported once from the login keychain
  and stored as repository secrets (the `.p12` in base64, and its
  password). The owner's own Mac then needs no re-grant, and a local
  `make install` carries the same signature as a release.
- **(call)** The owner also stores the `.p12` and its password in a
  password manager. The README says why.
- **(call)** A tag ruleset on GitHub restricts `v*` tags to the owner, so
  only the owner can trigger a signed release.

### Releasing

- **(call)** A release is published by creating a tag `vMAJOR.MINOR.PATCH`,
  on GitHub's Releases page or with `gh release create`. Nothing else is
  needed.
- A workflow triggered by that tag, on a macOS Apple Silicon runner:
  1. imports the certificate into a temporary keychain,
  2. builds the bundle with `scripts/bundle.sh`, signed through
     `CROPCAST_SIGN_IDENTITY`,
  3. stamps the version from the tag into `Info.plist`
     (`CFBundleShortVersionString`; `CFBundleVersion` from the run number),
     before signing,
  4. fails if the result is ad-hoc signed or the bundle version does not
     match the tag,
  5. zips the app with `ditto -c -k --keepParent` as `CropCast.zip`,
  6. attaches it to the GitHub release for the tag.
- A local `make app` keeps working without a tag and keeps the version
  that is in `Info.plist`.

### Development builds

- **(call)** Only builds made by the release workflow update themselves.
  The workflow marks them as release builds in `Info.plist` when it stamps
  the version. A build without the mark is a development build: it never
  checks for updates, shows no update menu item, and its Updates section
  in Settings says "Development build. Updates are off."
- Why: a local build from `main` still carries the version in
  `Info.plist`, so it would be offered the latest release and one click
  would replace newer code with an older release. A clone build signed
  with someone else's certificate would be offered every update and
  refuse each one.
- "A downloaded install and one built from a clone behave the same" means
  the app works the same. It does not mean clone builds update themselves.

### Finding an update

- **(call)** The app asks the GitHub API for the latest release of
  `sv-tmueller/cropcast` (`releases/latest`, which skips drafts and
  pre-releases), over HTTPS, without credentials.
- **(call)** It checks at launch and then once every 24 hours, and on
  demand from Settings. An automatic check that fails is logged and stays
  silent; a manual check that fails says why.
- **(call)** "Check for updates automatically" is a Settings toggle, on by
  default.
- A release is newer when its version is numerically higher than the
  running version (`0.10.0` is newer than `0.9.0`). A tag that is not a
  plain `vX.Y.Z`, or a release without `CropCast.zip`, is ignored.

### What the user sees

Menu bar menu, only while a newer release is known:

    Start Sharing
    Show Frame
    …
    Update to 0.2.0…
    Settings…
    Quit CropCast

Settings window, new section:

    Updates
      Version 0.1.0                                  [Check Now]
      [x] Check for updates automatically
      CropCast 0.2.0 is available.       [Install and Restart]

- **(call)** While a session is starting, sharing or stopping, the update
  cannot be installed. The menu item and the button are disabled and say
  "Stop sharing to update".
- After the click the app shows progress (downloading, installing) and
  then relaunches without another question. On any failure it says what
  went wrong and keeps running the current version.

### Installing

On the click, in this order. Any failed step stops the update and leaves
the installed app untouched.

1. Download `CropCast.zip` from the release to a temporary directory.
2. Unpack it there.
3. Verify the unpacked app:
   - its code signature is valid,
   - it satisfies the running app's own designated requirement (same
     bundle identifier, same certificate),
   - its version is higher than the running version.
4. Replace the installed bundle with the new one in a way that can be
   undone: the old bundle is kept until the new one is in place, and put
   back if the swap fails.
5. Relaunch: a small detached helper waits for the old process to exit and
   opens the app again. The app quits through the normal terminate path.

Cases that stop before step 1, each with a clear message:

- The app's folder is not writable for this user (for example a standard
  user and `/Applications`).
- The app runs from a read-only or translocated location (opened straight
  from Downloads). The message says to move it to Applications first.
- The app is a release build but its own signature is ad-hoc or invalid.
  There is nothing to compare a download's signature against.

Development builds never get this far (see "Development builds").

### First install

- The README gets an "Install" section for people without a clone:
  download `CropCast.zip` from the latest release, move the app to
  Applications, open it, allow it once in System Settings > Privacy &
  Security (macOS blocks apps that Apple has not checked), then grant
  Screen Recording at the first Start.
- `make install` stays for development.

## Unverified assumptions: test first

Three things cannot be observed on the owner's Mac, because the
certificate is trusted there, and cannot be observed by agents at all.
They are checked before anything else is built, on a second Mac or a
second user account that never ran `make signing-cert`. The app must
arrive there the way a user gets it: zipped, downloaded with a browser,
moved to Applications.

**A. The grant survives an update.**

1. Install build A (signed with the certificate), open it, allow it, grant
   Screen Recording, start a share.
2. Replace it by hand with build B (a different build, same certificate).
   Start a share.
3. Pass: no permission alert, the share works.

**B. The signature check works without trust.**

1. On that Mac, record what `codesign --verify --strict` and
   `codesign -d -r-` print for the installed app.
2. Run the check the updater will use (`SecStaticCodeCheckValidity` of
   build B against build A's designated requirement) from a throwaway
   command-line tool.
3. Pass: the check accepts build B and rejects a build signed ad-hoc or
   with another certificate, and rejects build B after one byte of its
   executable was changed.

**C. The app may replace itself.**

Since macOS 13, App Management protection can block or prompt when a
process changes an app bundle.

1. A throwaway build of the app gets a hidden action that replaces its own
   bundle with build B and relaunches.
2. Pass: it works with no prompt, or with one "CropCast would like to
   manage apps" prompt that does not come back on the next replacement.

**What follows from the results**

- A or B fails only because the certificate is not trusted: the first
  launch of a downloaded app offers to trust the CropCast certificate on
  that Mac (one password prompt), and explains why. The owner has accepted
  a certificate or permission step at first install. This adds a
  first-launch flow to work package 3 and a step to the README. The
  updater's check stays the full one.
- B cannot be made to work even with trust: stop and redesign. A check
  that only compares certificate hashes does not prove the bundle is
  untampered and is not an acceptable substitute.
- C prompts once per Mac: **(call)** acceptable; the README mentions it.
- C prompts on every update, or blocks: stop and bring it back to the
  owner before work package 2.

## Work packages

In order. Each is one issue, one branch, one PR.

0. **Tests A, B and C** (owner on the second Mac; throwaway code from an
   agent for B and C, not merged). See above.
1. **Release pipeline** (root: `scripts/`, `.github/workflows/`,
   `README.md`). Version stamping, the tag workflow, the one-time
   certificate export, the Install and Releasing sections of the README.
2. **`Packages/SelfUpdate`** (new package, independent like the others).
   Pure logic with unit tests: version parsing and comparison, decoding
   the release JSON, the decision "is there an update for me", the state
   machine of an update. Glue: the HTTPS check, download, unpack,
   signature verification, the undoable swap, the relaunch helper. A demo
   executable that checks and verifies against a real release without
   installing. README with a manual checklist.
3. **App wiring** (root package). The daily check, the menu item, the
   Updates section in Settings, the block while sharing, the relaunch
   through the normal quit path. Depends on 2.

Package 2 is likely larger than size:M. If so, split it into "check"
(find and offer) and "install" (download, verify, swap, relaunch).

## Left to the builder

- Type and file names, and how the update state reaches the menu and
  Settings.
- How the download is unpacked and how the swap is made undoable.
- The exact wording of messages, within the plain style of the app's
  existing alerts.
- Where the last-check time and the toggle are stored (UserDefaults keys
  in the style of the existing settings).
- Log lines: `os.Logger`, subsystem `com.github.sv-tmueller.cropcast`,
  category `update`, public privacy, never `.info` or `.debug`.

## Manual verification (owner)

- [ ] Tag `v0.2.0`: a release appears with `CropCast.zip`; the app inside
      reports 0.2.0 and is signed with the certificate.
- [ ] Fresh Mac: download, move to Applications, allow, grant, share.
- [ ] With 0.2.0 installed, publish `v0.2.1`: within a day, or after
      Check Now, the menu shows "Update to 0.2.1…".
- [ ] Click it: the app restarts as 0.2.1, a share starts with no
      permission alert, Launch at login and the other settings are kept.
- [ ] During a share the update cannot be started.
- [ ] A release asset that is not signed with the certificate is refused
      and the installed app keeps working.
- [ ] Offline: the automatic check is silent, Check Now says why it failed.

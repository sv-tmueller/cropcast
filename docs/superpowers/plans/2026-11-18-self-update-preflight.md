# Self-update preflight tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Find out, on a Mac that does not trust the CropCast certificate, whether the three assumptions behind the self-update design hold, before any of it is built.

**Architecture:** A throwaway spike. An agent on the owner's Mac prepares test builds and one small tool on a branch that is never merged. The owner runs a written checklist on a second Mac and reports what happened. The agent records the results in the spec and says which follow-up applies.

**Tech Stack:** Swift 6, SwiftPM, Command Line Tools only. Security framework (`SecStaticCode`), `codesign`, `ditto`, `gh`.

**Spec:** `docs/superpowers/specs/2026-11-18-cropcast-self-update-design.md`, section "Unverified assumptions: test first". This plan covers work package 0 only. Packages 1 to 3 get their own plans after the results, because the results can change them.

## Global Constraints

- Everything built here is throwaway: no unit tests, no PR, nothing merged to `main`. Only the results (Task 3) reach `main`.
- Branch name: `spike/self-update-preflight`.
- No third-party dependencies. No Xcode.
- Never change the owner's login keychain, trust settings or `/Applications/CropCast.app` on the owner's Mac. Local sanity checks use `CROPCAST_INSTALL_DIR` pointing at a temporary folder.
- Test builds are published only as assets of a **draft** GitHub release named `preflight`. Never a public release or pre-release.
- Agents have no Screen Recording grant and no second Mac. Task 2 is the owner's.
- The second Mac must never have run `make signing-cert` and must not have `CropCast Self-Signed` in any keychain.

## Review Focus

Conditions that would make a "pass" meaningless. Each is pinned in the task named.

1. **The app did not arrive as a download.** Without the quarantine flag macOS skips the checks a real user hits. Task 2 checks the flag before anything else.
2. **A second user account on the owner's own Mac instead of a second Mac.** As far as known, Screen Recording grants are stored per Mac, not per user, so the owner's existing grant would already cover the test account. Task 2 resets the grant first in that case. The test app then lives in the test account's `~/Applications`, and macOS may treat that folder differently from `/Applications` for test C, so Task 3 marks such a result as provisional.
3. **Build B is not really different from build A.** Then "the grant survived an update" proves nothing. Task 1 gives B another version and Task 2 reads it back.
4. **The self-replacement was done by Terminal or Finder, not by CropCast.** macOS attributes the change to the process that makes it. Task 1 puts the replacement inside the app; Task 2 only starts it.
5. **The replaced bundle picked up the quarantine flag from the downloaded zip.** A real update is downloaded by the app itself and would not carry it. Task 1 logs the flag on the new bundle so the result can be read with that in mind.

---

### Task 1: Test builds and the verify tool (agent, owner's Mac)

**Files (all on `spike/self-update-preflight`, never merged):**
- Create: `Sources/PreflightVerify/main.swift`
- Create: `Sources/CropCast/PreflightReplace.swift`
- Modify: `Package.swift` (add the `PreflightVerify` executable target)
- Modify: `Sources/CropCast/main.swift` (call the hidden action at launch)
- Output: `build/preflight/` (not committed)

**Interfaces:**
- Produces, for Task 2:
  - `preflight-verify <reference.app> <candidate.app>`: prints the reference's designated requirement, then `ACCEPT` or `REJECT <OSStatus> <message>` for the candidate. Exit status 0 for accept, 1 for reject.
  - Launch argument `--preflight-replace-with <zip path>` on the CropCast test builds.
  - Log file `~/Desktop/cropcast-preflight.log`.
  - Assets `CropCast-A.zip`, `CropCast-B.zip`, `CropCast-adhoc.zip`, `CropCast-othercert.zip`, `CropCast-B-tampered.zip`, `preflight-verify`.

- [ ] **Step 1: Create the branch** `spike/self-update-preflight` from `main`.

- [ ] **Step 2: Write `preflight-verify`.**
  It creates a `SecStaticCode` for each path, reads the reference's designated requirement with `SecCodeCopyDesignatedRequirement`, and checks the candidate with `SecStaticCodeCheckValidity` using the flags `kSecCSCheckAllArchitectures`, `kSecCSCheckNestedCode` and `kSecCSStrictValidate` and that requirement. This is the check the real updater is meant to use, so do not weaken it to make a case pass.

- [ ] **Step 3: Write the hidden action.**
  When the app is launched with `--preflight-replace-with <zip path>`, the CropCast process itself, with no helper doing the file work:
  1. unpacks the zip into a temporary folder with `/usr/bin/ditto -x -k`,
  2. logs whether the unpacked app carries `com.apple.quarantine`,
  3. moves its own bundle (`Bundle.main.bundleURL`) to the temporary folder and moves the unpacked app into its place; on failure moves the old one back,
  4. starts a detached `/bin/sh` that waits for this process to exit and then runs `open` on the bundle path,
  5. terminates.
  Every step and every error, with its domain and code, is appended to `~/Desktop/cropcast-preflight.log` with a timestamp. Without the argument the app behaves exactly like `main`.

- [ ] **Step 4: Build the artifacts into `build/preflight/`.**

  | Asset | Version in `Info.plist` | Signed with |
  |---|---|---|
  | `CropCast-A.zip` | 0.1.0 | `CropCast Self-Signed` |
  | `CropCast-B.zip` | 0.1.1 | `CropCast Self-Signed` |
  | `CropCast-adhoc.zip` | 0.1.1 | ad-hoc (`CROPCAST_SIGN_IDENTITY=-`) |
  | `CropCast-othercert.zip` | 0.1.1 | a second, throwaway self-signed certificate |
  | `CropCast-B-tampered.zip` | 0.1.1 | as B, then one byte of `Contents/MacOS/CropCast` changed after signing |

  Zip each with `ditto -c -k --keepParent`. Change the version in a working copy of `Info.plist`, not in a commit. For `othercert`, use a temporary keychain (`scripts/signing-cert.sh` has the `CROPCAST_SIGNING_KEYCHAIN` hook). If that cannot be done without touching the login keychain or the trust settings, skip this asset and say so in the results.

- [ ] **Step 5: Sanity-check on the owner's Mac.**

  Run: `preflight-verify` with A as the reference against B, adhoc, othercert and B-tampered.
  Expected: `ACCEPT` for B, `REJECT` for the other three. If B is rejected here, where the certificate is trusted, stop and report: the check itself is wrong.

  Run: install A into a temporary `CROPCAST_INSTALL_DIR`, launch it with `--preflight-replace-with <path to CropCast-B.zip>`.
  Expected: the app relaunches, the installed bundle reports 0.1.1 (`defaults read <app>/Contents/Info CFBundleShortVersionString`), and the log shows every step.

- [ ] **Step 6: Publish for the owner.**
  Push the branch. Create a draft release with `gh release create preflight --draft` and attach the six assets. Post the Task 2 checklist as a comment on the issue, with the asset links.

### Task 2: Run the tests on the second Mac (owner)

The owner does this by hand and writes down what happens at every "Record" line. A prompt that appears, and its exact title, is a result, not a nuisance.

- [ ] **Step 1: Prepare.**
  - Download all six assets with a browser, logged in to GitHub (draft assets are private).
  - Set where the test app lives, and use `$APP` in every command below:
    - on a second Mac: `APP=/Applications/CropCast.app`
    - on a second user account of the owner's Mac: `mkdir -p ~/Applications; APP="$HOME/Applications/CropCast.app"`. The owner's real install in `/Applications` must stay untouched.
  - Only on a second user account: quit CropCast in the owner's account first, then run `tccutil reset ScreenCapture com.github.sv-tmueller.cropcast`. The owner's own account will need the grant again afterwards.
  - Unzip `CropCast-A.zip` by double-clicking and move the app to the folder `$APP` is in.
  - Run `xattr -p com.apple.quarantine "$APP"`. Expected: a value is printed. If it says "No such xattr", stop: the app did not arrive as a download.
  - Run `security find-identity -p codesigning`. Expected: `CropCast Self-Signed` is not listed.

- [ ] **Step 2: Test A, the grant survives an update.**
  1. Open CropCast. Record what macOS shows and what it took to open it.
  2. Start Sharing, grant Screen Recording, reopen when macOS asks, Start Sharing again. Expected: the share runs (red frame, menu reads "Stop Sharing"). Stop Sharing, quit.
  3. Unzip `CropCast-B.zip` and drag the app into the same folder, choosing Replace.
  4. Run `defaults read "$APP/Contents/Info" CFBundleShortVersionString`. Expected: `0.1.1`.
  5. Open CropCast. Record whether macOS asked to allow it again.
  6. Start Sharing. **Pass:** no permission alert and the share runs. Record the result. Stop Sharing, quit.

- [ ] **Step 3: Test B, the signature check works without trust.**
  1. Run `codesign --verify --strict --verbose=2 "$APP"` and `codesign -d -r- "$APP"`. Record both outputs in full.
  2. Make the tool runnable: `xattr -d com.apple.quarantine preflight-verify; chmod +x preflight-verify`.
  3. Unzip the adhoc, othercert and B-tampered zips into separate folders. Run `./preflight-verify "$APP" <candidate>` for a fresh unzip of B and for each of the three. Record every output line.
  4. **Pass:** `ACCEPT` for B, `REJECT` for the other three.

- [ ] **Step 4: Test C, the app may replace itself.**
  1. Run `open -a "$APP" --args --preflight-replace-with "$HOME/Downloads/CropCast-A.zip"`. Record every prompt macOS shows, with its title, and what was clicked.
  2. Expected: CropCast relaunches and the version reads `0.1.0`. Record whether macOS asked to allow the app again after the relaunch.
  3. Repeat with `CropCast-B.zip`. Record whether any prompt from step 1 came back. Expected version: `0.1.1`.
  4. Start Sharing. Record whether a permission alert appeared.
  5. **Pass:** both replacements worked, with no prompt or with one "manage apps" prompt that did not come back, and the share ran with no permission alert.

- [ ] **Step 5: Report.** Post the recorded results and the contents of `~/Desktop/cropcast-preflight.log` as a comment on the issue.

### Task 3: Record the results and name the follow-up (agent)

**Files:**
- Modify: `docs/superpowers/specs/2026-11-18-cropcast-self-update-design.md`

- [ ] **Step 1: Add a "Results" subsection** under "Unverified assumptions: test first": the date, the macOS version of the second Mac, whether it was a second Mac or a second account, and pass or fail for A, B and C with the recorded outputs that support each. If it was a second account, mark the results as provisional and say that they must be repeated on a real second Mac before CropCast is rolled out to anyone else.

- [ ] **Step 2: State which branch of "What follows from the results" applies**, in the spec and as a comment on the issue. If a result fits none of the branches, say so and stop: that is a question for the owner, not a call for the agent.

- [ ] **Step 3: Update the spec's Status line** to say the assumptions were tested and what the outcome was.

- [ ] **Step 4: Open a docs PR** for the spec change (`docs: record self-update preflight results`, `Closes #52`).

- [ ] **Step 5: Clean up after the PR is merged.** Delete the draft release `preflight` and the branch `spike/self-update-preflight`, and remove the throwaway certificate's temporary keychain.

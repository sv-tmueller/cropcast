#!/usr/bin/env bash
# Install or remove CropCast.app (macOS/Command Line Tools only, never sudo).
#
#   scripts/install.sh install     copy build/CropCast.app into the install dir
#   scripts/install.sh uninstall   remove CropCast.app from the install dir
#
# Install dir: $CROPCAST_INSTALL_DIR, default /Applications. The script never
# creates the dir. If it is not writable, use CROPCAST_INSTALL_DIR="$HOME/Applications".
#
# A running CropCast is quit first, but only an instance running from the very
# bundle being replaced (matched on bundle id and bundle path), so a copy in
# another directory is left alone. Quit is graceful (terminate), then SIGTERM
# to those pids only. If an instance is still alive, the script aborts without
# touching the installed bundle. The bundle is not re-signed (copied as built).
# See README.md, "Stable code signing".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/build/CropCast.app"
BUNDLE_ID="com.github.sv-tmueller.cropcast"
DIR="${CROPCAST_INSTALL_DIR:-/Applications}"

die() { echo "error: $*" >&2; exit 1; }

# JXA helpers. Arguments go in via argv, never pasted into the JS source.
# Print "<pid><TAB><bundle path>" for every running CropCast instance.
list_instances() {
  osascript -l JavaScript -e '
    function run(argv) {
      ObjC.import("AppKit");
      const apps = $.NSRunningApplication
        .runningApplicationsWithBundleIdentifier(argv[0]);
      const lines = [];
      for (let i = 0; i < apps.count; i++) {
        const app = apps.objectAtIndex(i);
        lines.push(app.processIdentifier + "\t" + ObjC.unwrap(app.bundleURL.path));
      }
      return lines.join("\n");
    }' "$BUNDLE_ID"
}

# Ask each given pid to terminate gracefully (like Cmd-Q).
terminate_pids() {
  osascript -l JavaScript -e '
    function run(argv) {
      ObjC.import("AppKit");
      for (const pid of argv) {
        const app = $.NSRunningApplication
          .runningApplicationWithProcessIdentifier(parseInt(pid, 10));
        if (!app.isNil()) app.terminate; // zero-arg ObjC methods are properties in JXA
      }
    }' "$@" >/dev/null
}

# Print the pids of CropCast instances running from the bundle $1, given the
# list_instances output $2. Paths are compared after resolving symlinks in the
# shell (Foundation maps /private/tmp to /tmp, so it cannot be trusted for this).
matching_pids() {
  local pid path real
  while IFS=$'\t' read -r pid path; do
    [[ -n "$pid" && -d "$path" ]] || continue
    real="$(cd "$path" && pwd -P)"
    [[ "$real" == "$1" ]] && printf '%s ' "$pid"
  done <<<"$2"
  return 0
}

alive() { # true if any of the given pids is still running
  local pid
  for pid in "$@"; do
    kill -0 "$pid" 2>/dev/null && return 0
  done
  return 1
}

wait_gone() { # wait_gone <seconds> <pid>...: poll every 0.2 s
  local ticks=$(($1 * 5))
  shift
  while ((ticks-- > 0)); do
    alive "$@" || return 0
    sleep 0.2
  done
  alive "$@" && return 1
  return 0
}

quit_running() { # quit_running <bundle path>
  local out pids
  # Fail closed: a listing failure must not read as "not running".
  out="$(list_instances)" || die "could not list running CropCast instances; nothing was changed"
  read -ra pids <<<"$(matching_pids "$1" "$out")"
  ((${#pids[@]} > 0)) || return 0
  echo "Quitting running CropCast (${pids[*]}) from $1"
  terminate_pids "${pids[@]}"
  if wait_gone 5 "${pids[@]}"; then return 0; fi
  echo "Still running; sending SIGTERM to ${pids[*]}"
  kill -TERM "${pids[@]}" 2>/dev/null || true
  if wait_gone 2 "${pids[@]}"; then return 0; fi
  die "CropCast (${pids[*]}) is still running from $1; quit it and re-run. Nothing was changed."
}

preflight_dir() { # preflight_dir <dir>: dir exists and is writable
  [[ -d "$1" ]] || die "install dir '$1' does not exist (it is never created). Try CROPCAST_INSTALL_DIR=\"\$HOME/Applications\"."
  [[ -w "$1" ]] || die "install dir '$1' is not writable (sudo is never used). Try CROPCAST_INSTALL_DIR=\"\$HOME/Applications\"."
}

preflight_dest() { # an existing bundle must be ours to replace
  if [[ -e "$DEST" && ! -O "$DEST" ]]; then
    die "'$DEST' is not owned by you (sudo is never used). Try CROPCAST_INSTALL_DIR=\"\$HOME/Applications\"."
  fi
}

# Safety net before any rm -rf.
assert_dest() {
  [[ "$DEST" == */CropCast.app ]] || die "refusing to remove '$DEST' (not a CropCast.app path)"
}

do_install() {
  preflight_dir "$DIR"
  [[ -d "$SRC" ]] || die "$SRC not found; run 'make app' first (or use 'make install')."
  preflight_dest

  # Stage a clean copy and verify it strictly before touching anything. A synced
  # folder (iCloud Desktop, Dropbox) adds Finder xattrs to build/ after signing,
  # which only --strict rejects; the copy drops them. A bad bundle therefore
  # aborts here, while the old install and any running instance are untouched.
  STAGE="$(mktemp -d "${TMPDIR:-/tmp}/cropcast-stage.XXXXXX")"
  trap 'rm -rf "$STAGE"' EXIT
  ditto --norsrc --noextattr "$SRC" "$STAGE/CropCast.app"
  codesign --verify --strict "$STAGE/CropCast.app" || die "$SRC failed codesign verification; run 'make app' again."

  quit_running "$DEST"

  assert_dest
  rm -rf "$DEST"
  ditto --norsrc --noextattr "$STAGE/CropCast.app" "$DEST"
  codesign --verify --strict "$DEST" || die "$DEST failed codesign verification after the copy."
  echo "Installed $DEST"

  if [[ "$(codesign -dv "$DEST" 2>&1)" == *"Signature=adhoc"* ]]; then
    echo
    echo "Note: this copy is signed ad-hoc, so an earlier Screen Recording grant does not"
    echo "apply to it. To start clean, run:"
    echo "  tccutil reset ScreenCapture $BUNDLE_ID"
    echo "then re-grant on first launch. A stable signing identity avoids this:"
    echo "run 'make signing-cert' once, then 'make install' again"
    echo "(README.md, \"Stable code signing\")."
  fi
  echo
  echo "Launch it with:"
  echo "  open \"$DEST\""
}

do_uninstall() {
  if [[ ! -e "$DEST" ]]; then
    echo "CropCast is not installed in $DIR"
    return 0
  fi
  preflight_dir "$DIR"
  preflight_dest

  quit_running "$DEST"

  assert_dest
  rm -rf "$DEST"
  echo "Removed $DEST"
  echo "Preferences were left in place; 'defaults delete $BUNDLE_ID' removes them."
}

[[ "$EUID" -ne 0 ]] || die "do not run as root (use CROPCAST_INSTALL_DIR=\"\$HOME/Applications\" instead)"

# Resolve symlinks (/tmp, /var, ...) so the path matches what the OS reports.
if [[ -d "$DIR" ]]; then
  DIR="$(cd "$DIR" && pwd -P)"
fi
DEST="$DIR/CropCast.app"

case "${1:-}" in
  install) do_install ;;
  uninstall) do_uninstall ;;
  *) echo "usage: $0 install|uninstall" >&2; exit 2 ;;
esac

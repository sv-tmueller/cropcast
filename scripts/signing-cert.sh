#!/usr/bin/env bash
# Create and trust the self-signed code-signing certificate "CropCast Self-Signed"
# in the login keychain (macOS/Command Line Tools only, never sudo). Run it via
# `make signing-cert`. `make app` then signs with it, so the Screen Recording
# grant survives rebuilds. See README.md, "Stable code signing".
#
#   - Already set up: prints the SHA-1 and changes nothing.
#   - Certificate present but untrusted (cancelled prompt, or created by hand in
#     Keychain Access): only asks for trust again; never imports a second one.
#   - Expired or ambiguous: reports it and stops; this script never deletes
#     keychain items.
#
# Trusting changes the user's trust settings, which macOS guards with one
# password / Touch ID prompt (no sudo).
#
# Test hook: CROPCAST_SIGNING_KEYCHAIN=<keychain file> works on that keychain
# instead of the login keychain and skips the trust step. Trust settings are per
# user, not per keychain, so trusting would change the real store even when the
# certificate sits in a throwaway keychain.
set -euo pipefail

NAME="CropCast Self-Signed"
# Pin LibreSSL: a Homebrew OpenSSL 3 earlier in PATH writes a PKCS#12 that
# `security import` cannot read.
OPENSSL=/usr/bin/openssl

die() { echo "error: $*" >&2; exit 1; }

[[ "$EUID" -ne 0 ]] || die "do not run as root (the login keychain would be root's)"

SKIP_TRUST=0
if [[ -n "${CROPCAST_SIGNING_KEYCHAIN:-}" ]]; then
  KC="$CROPCAST_SIGNING_KEYCHAIN"
  SKIP_TRUST=1
else
  # Strip only the leading indent and the surrounding quotes; the path may
  # contain spaces.
  KC="$(security login-keychain | sed 's/^ *"//; s/"$//')"
fi
[[ -f "$KC" ]] || die "keychain not found: $KC"

# Lines look like: 1) <SHA-1> "CropCast Self-Signed" [(CSSMERR_TP_NOT_TRUSTED)]
# find-identity exits 0 when nothing matches, so a failure is a real lookup
# error. It must stop the script: treating it as "no identity" would go on to
# create a second certificate. Only grep (no match) is allowed to fail.
# Callers must assign the result (`x="$(identity_lines)"`) so that set -e sees
# the failure; die only ends the command substitution's subshell.
identity_lines() { # [-v]
  local out
  out="$(security find-identity "$@" -p codesigning "$KC")" ||
    die "could not list code-signing identities in $KC"
  printf '%s\n' "$out" | { grep -F "\"$NAME\"" || true; }
}
count_lines() { # <text>; counts non-empty lines
  printf '%s\n' "$1" | grep -c . || true
}
sha_of() { # <identity line>
  printf '%s\n' "$1" | awk '{print $2}'
}

valid="$(identity_lines -v)"
if [[ -n "$valid" ]]; then
  # With several valid identities bundle.sh signs with the first match; so do we.
  echo "'$NAME' is already set up ($(sha_of "$(printf '%s\n' "$valid" | head -n 1)"))"
  exit 0
fi

all="$(identity_lines)"
resume=0
if [[ -n "$all" ]]; then
  if [[ "$(count_lines "$all")" -eq 1 && "$all" == *"(CSSMERR_TP_NOT_TRUSTED)" ]]; then
    resume=1
  else
    die "found a '$NAME' identity that is not usable:
$all
Delete it in Keychain Access (login keychain), then run 'make signing-cert' again."
  fi
fi

umask 077
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cropcast-cert.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM

if [[ "$resume" -eq 1 ]]; then
  echo "Found an untrusted '$NAME' certificate; not creating another one."
  sha="$(sha_of "$all")"
  security find-certificate -a -Z -p -c "$NAME" "$KC" | awk -v sha="$sha" '
    /^SHA-1 hash:/ { want = ($3 == sha) }
    /-----BEGIN CERTIFICATE-----/ { if (want) on = 1 }
    on { print }
    /-----END CERTIFICATE-----/ { on = 0 }
  ' > "$TMP/cert.pem"
  [[ -s "$TMP/cert.pem" ]] || die "could not export the certificate $sha from $KC"
else
  CROPCAST_CERT_PW="$("$OPENSSL" rand -hex 16)"
  export CROPCAST_CERT_PW
  cat > "$TMP/req.cnf" <<CNF
[req]
prompt = no
distinguished_name = dn
x509_extensions = codesign
[dn]
CN = $NAME
[codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
  # Ten years: an expired certificate silently sends bundle.sh back to ad-hoc.
  "$OPENSSL" req -x509 -config "$TMP/req.cnf" -newkey rsa:2048 -sha256 -days 3650 \
    -set_serial "0x$("$OPENSSL" rand -hex 8)" \
    -keyout "$TMP/key.pem" -passout env:CROPCAST_CERT_PW -out "$TMP/cert.pem" 2>"$TMP/req.log" ||
    die "openssl could not create the certificate:
$(cat "$TMP/req.log")"
  # Explicit legacy algorithms so `security import` can read the file.
  "$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -passin env:CROPCAST_CERT_PW \
    -in "$TMP/cert.pem" -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout env:CROPCAST_CERT_PW -out "$TMP/id.p12"
  # No set-key-partition-list (needs the login password) and no -A.
  security import "$TMP/id.p12" -k "$KC" -f pkcs12 -P "$CROPCAST_CERT_PW" -T /usr/bin/codesign >/dev/null
  echo "Created '$NAME' (RSA 2048, valid 10 years) in $KC"
fi

if [[ "$SKIP_TRUST" -eq 1 ]]; then
  echo "trust skipped (CROPCAST_SIGNING_KEYCHAIN is set)"
  seen="$(identity_lines)"
  [[ "$(count_lines "$seen")" -eq 1 ]] || die "expected exactly one '$NAME' identity in $KC"
  exit 0
fi

echo "Trusting it for code signing; macOS will ask for your password or Touch ID."
security add-trusted-cert -r trustRoot -p codeSign -k "$KC" "$TMP/cert.pem" ||
  die "trust not granted; the certificate is in your login keychain; run make signing-cert again to retry. It will not create a second one."

final="$(identity_lines -v)"
[[ -n "$final" ]] || die "'$NAME' is not listed as a valid code-signing identity"
echo "'$NAME' is ready ($(sha_of "$final"))"
echo "Next: run 'make app' (or 'make install'). Reset the stale Screen Recording grant once:"
echo "  tccutil reset ScreenCapture com.github.sv-tmueller.cropcast"

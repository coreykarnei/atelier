#!/usr/bin/env bash
# Build the release zip: a release build, signed with the Developer ID
# (hardened runtime, secure timestamp), notarized by Apple and stapled, so a
# downloaded copy — the Homebrew cask's included — opens without Gatekeeper's
# quarantine prompt.
#
# The Developer ID identity and the notary credentials live in their own
# keychain, locked except while this script runs: in the login keychain,
# codesign could use the key without asking, so any process running as the
# user could sign as the team. One-time setup is in docs/SETUP.md,
# "Releasing".
#
# Overrides: RELEASE_KEYCHAIN=<path> (default
# ~/Library/Keychains/release.keychain-db), DEVELOPER_ID="Developer ID
# Application: … (TEAMID)", NOTARY_PROFILE=<keychain profile> (default
# atelier-notary).
#
# `release.sh --check` unlocks the keychain, test-signs a scratch binary,
# checks the notary credentials, and locks it again — no build.
#
# Dev builds keep the self-signed identity (Scripts/bundle.sh); only this
# script touches the Developer ID.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/Atelier.app"
DIST="$ROOT/.build/dist"
KEYCHAIN="${RELEASE_KEYCHAIN:-$HOME/Library/Keychains/release.keychain-db}"
NOTARY_PROFILE="${NOTARY_PROFILE:-atelier-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$DIST/Atelier-$VERSION.zip"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "error: no release keychain at $KEYCHAIN (docs/SETUP.md, \"Releasing\")" >&2
  exit 1
fi
if security find-identity -v -p codesigning | grep -q '"Developer ID Application:'; then
  echo "warning: a Developer ID identity is still on the keychain search list;" >&2
  echo "         it belongs only in $KEYCHAIN (docs/SETUP.md, \"Releasing\")" >&2
fi

# Unlocked only from here to exit, whatever the exit; the keychain's own
# auto-lock is the backstop.
unlock() {
  echo "==> unlocking $(basename "$KEYCHAIN")"
  security unlock-keychain "$KEYCHAIN"
  trap 'security lock-keychain "$KEYCHAIN"; echo "==> keychain locked"' EXIT
  if [[ -z "${DEVELOPER_ID:-}" ]]; then
    DEVELOPER_ID="$(security find-identity -v -p codesigning "$KEYCHAIN" \
      | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
  fi
  if [[ -z "$DEVELOPER_ID" ]]; then
    echo "error: no 'Developer ID Application' identity in $KEYCHAIN" >&2
    exit 1
  fi
}

sign() {
  codesign --force --options runtime --timestamp --keychain "$KEYCHAIN" \
    --sign "$DEVELOPER_ID" "$@"
}

notary() {
  xcrun notarytool "$@" --keychain-profile "$NOTARY_PROFILE" --keychain "$KEYCHAIN"
}

if [[ "${1:-}" == "--check" ]]; then
  unlock
  SCRATCH="$(mktemp -d)"
  cp /bin/echo "$SCRATCH/probe"
  sign "$SCRATCH/probe"
  codesign --verify --verbose=1 "$SCRATCH/probe"
  rm -rf "$SCRATCH"
  echo "==> signing works as: $DEVELOPER_ID"
  notary history >/dev/null
  echo "==> notary credentials work ($NOTARY_PROFILE)"
  exit 0
fi

echo "==> Atelier $VERSION"
echo "==> release build"
swift build -c release
"$ROOT/Scripts/bundle.sh" release >/dev/null

unlock
echo "==> signing as: $DEVELOPER_ID"
# Inside out: the helper binaries first, then the app, which seals them and
# every resource. The bundle is re-signed from scratch — bundle.sh's
# self-signed signature is replaced, not layered.
sign "$APP/Contents/MacOS/atelier-notify"
sign "$APP/Contents/MacOS/atelier-cli"
sign "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "==> notarizing (usually a few minutes)"
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if ! notary submit "$ZIP" --wait --output-format plist > "$DIST/notary.plist"; then
  cat "$DIST/notary.plist" >&2 || true
  exit 1
fi
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$DIST/notary.plist")"
ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$DIST/notary.plist")"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "error: notarization $STATUS — the log says why:" >&2
  notary log "$ID" >&2
  exit 1
fi

echo "==> stapling"
# The ticket travels in the bundle, so Gatekeeper needn't reach Apple on
# first launch. The zip is rebuilt around the stapled app.
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose=2 "$APP"

echo
echo "built $ZIP"
echo "sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo
echo "Note: .build/Atelier.app is now the Developer ID release build; 'make bundle'"
echo "returns it to a self-signed debug build."

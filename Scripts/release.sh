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
# auto-lock is the backstop. It also joins the user's keychain search list
# for that span: `codesign --keychain` picks the identity there, but finds
# its private key through the search list, so a keychain off the list fails
# with "The specified item could not be found in the keychain". The list
# goes back to exactly what it was.
unlock() {
  echo "==> unlocking $(basename "$KEYCHAIN")"
  security unlock-keychain "$KEYCHAIN"
  SEARCH_LIST=()
  while IFS= read -r entry; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry#\"}"
    entry="${entry%\"}"
    [[ -n "$entry" && "$entry" != "$KEYCHAIN" ]] && SEARCH_LIST+=("$entry")
  done < <(security list-keychains -d user)
  trap 'security list-keychains -d user -s "${SEARCH_LIST[@]}"; security lock-keychain "$KEYCHAIN"; echo "==> keychain locked"' EXIT
  security list-keychains -d user -s "${SEARCH_LIST[@]}" "$KEYCHAIN"
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

# What ships is what's committed and tagged: no stray edits, no untracked
# files, HEAD at v$VERSION — and the one prebuilt binary in the tree is the
# upstream file it claims to be (Vendor/CodeEditLanguages/ATELIER.md).
if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "error: the tree has uncommitted or untracked changes — release from a clean checkout" >&2
  exit 1
fi
if [[ "$(git -C "$ROOT" tag --points-at HEAD)" != *"v$VERSION"* ]]; then
  echo "error: HEAD isn't tagged v$VERSION (Info.plist's version) — commit, tag, then release" >&2
  exit 1
fi
GRAMMARS="$ROOT/Vendor/CodeEditLanguages/CodeLanguagesContainer.xcframework.zip"
GRAMMARS_SHA256=c6ee69d9d373a9c3cf93d239e05369d9b941275d31cd7956d0dc83b5a5c3e152
if [[ "$(shasum -a 256 "$GRAMMARS" | cut -d' ' -f1)" != "$GRAMMARS_SHA256" ]]; then
  echo "error: $GRAMMARS isn't the recorded upstream file (Vendor/CodeEditLanguages/ATELIER.md)" >&2
  exit 1
fi

echo "==> Atelier $VERSION"
echo "==> release build"
swift build -c release
# The dev probe surface (Package.swift, ATELIER_PROBES) must not ship: it
# types into terminals and performs selectors for whoever reaches the socket.
if strings "$(swift build -c release --show-bin-path)/Atelier" | grep -q -E 'probe:|DebugMessage'; then
  echo "error: the release binary carries the probe surface (ATELIER_PROBES leaked into release)" >&2
  exit 1
fi
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
echo "Note: .build/Atelier.app is the Developer ID release build; debug builds"
echo "('make bundle') go to .build/AtelierDev.app and leave it alone."

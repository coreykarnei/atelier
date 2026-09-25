#!/usr/bin/env bash
# Build the release zip: a release build, signed with the Developer ID
# (hardened runtime, secure timestamp), notarized by Apple and stapled, so a
# downloaded copy — the Homebrew cask's included — opens without Gatekeeper's
# quarantine prompt.
#
# One-time setup (docs/SETUP.md, "Releasing"):
#   - a "Developer ID Application" certificate in the login keychain
#     (Xcode → Settings → Accounts → Manage Certificates → + )
#   - notary credentials stored as a keychain profile:
#       xcrun notarytool store-credentials atelier-notary \
#         --key <AuthKey_ID.p8> --key-id <ID> --issuer <issuer uuid>
#
# Overrides: DEVELOPER_ID="Developer ID Application: … (TEAMID)",
# NOTARY_PROFILE=<keychain profile> (default atelier-notary).
#
# Dev builds keep the self-signed identity (Scripts/bundle.sh); only this
# script touches the Developer ID.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/Atelier.app"
DIST="$ROOT/.build/dist"
NOTARY_PROFILE="${NOTARY_PROFILE:-atelier-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$DIST/Atelier-$VERSION.zip"

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "$DEVELOPER_ID" ]]; then
  echo "error: no 'Developer ID Application' identity in the keychain" >&2
  echo "       (Xcode → Settings → Accounts → Manage Certificates → + )" >&2
  exit 1
fi
echo "==> Atelier $VERSION, signing as: $DEVELOPER_ID"

echo "==> release build"
swift build -c release
"$ROOT/Scripts/bundle.sh" release >/dev/null

echo "==> signing"
# Inside out: the helper binaries first, then the app, which seals them and
# every resource. The bundle is re-signed from scratch — bundle.sh's
# self-signed signature is replaced, not layered.
sign() {
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID" "$@"
}
sign "$APP/Contents/MacOS/atelier-notify"
sign "$APP/Contents/MacOS/atelier-cli"
sign "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "==> notarizing (usually a few minutes)"
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist \
     > "$DIST/notary.plist"; then
  cat "$DIST/notary.plist" >&2 || true
  exit 1
fi
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$DIST/notary.plist")"
ID="$(/usr/libexec/PlistBuddy -c 'Print :id' "$DIST/notary.plist")"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "error: notarization $STATUS — the log says why:" >&2
  xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE" >&2
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

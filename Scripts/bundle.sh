#!/usr/bin/env bash
# Assemble Atelier.app from the SwiftPM build product. SwiftPM produces a bare
# Mach-O executable; macOS needs a .app bundle (with Info.plist → bundle id) for a
# Dock icon, proper activation, and — later — UNUserNotification delivery.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/.build/arm64-apple-macosx/$CONFIG"
APP="$ROOT/.build/Atelier.app"

if [[ ! -x "$BIN_DIR/Atelier" ]]; then
  echo "error: $BIN_DIR/Atelier not found — run 'swift build' (config: $CONFIG) first" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Atelier" "$APP/Contents/MacOS/Atelier"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ship the hook helper inside the bundle so Claude Code hooks reference one stable
# path (Contents/MacOS/atelier-notify) regardless of where the .app lives.
if [[ -x "$BIN_DIR/atelier-notify" ]]; then
  cp "$BIN_DIR/atelier-notify" "$APP/Contents/MacOS/atelier-notify"
fi

# Codesign with the stable self-signed identity if present (see
# Scripts/make-signing-cert.sh) so macOS persists TCC grants across rebuilds.
# Fall back to ad-hoc if it isn't installed — the app still runs, but you'll be
# re-prompted for permissions on every launch until you create the identity.
SIGN_IDENTITY="Atelier Code Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1 \
    && echo "signed with '$SIGN_IDENTITY'" \
    || echo "warning: signing with '$SIGN_IDENTITY' failed; app is unsigned"
else
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
  echo "note: ad-hoc signed (run ./Scripts/make-signing-cert.sh to stop per-launch permission prompts)"
fi

echo "built $APP"

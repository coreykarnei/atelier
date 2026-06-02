#!/usr/bin/env bash
# Create a stable, self-signed code-signing identity for Atelier.
#
# Why this exists: macOS will NOT persist TCC permission grants (Documents,
# Desktop, "data from other apps", etc.) for ad-hoc / unsigned apps. The grant is
# keyed to a stable signing identity; an ad-hoc signature's identity is the binary
# hash, which changes every build — so every launch re-prompts. Signing with a
# persistent self-signed cert gives the app one identity across rebuilds, so you
# grant each permission once and macOS remembers.
#
# Run once:  ./Scripts/make-signing-cert.sh
# It is idempotent — re-running is a no-op once the identity exists.
set -euo pipefail

IDENTITY_NAME="Atelier Code Signing"
LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
  echo "Signing identity '$IDENTITY_NAME' already present. Nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Generating self-signed code-signing certificate (valid 10 years)..."
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$IDENTITY_NAME" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# -legacy: OpenSSL 3.x defaults to a PKCS#12 MAC that Apple's `security` tool
# cannot verify ("MAC verification failed"). The legacy 3DES/RC2 format imports
# cleanly. (LibreSSL/older openssl already write this format and ignore the flag.)
LEGACY=""
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then LEGACY="-legacy"; fi
openssl pkcs12 -export $LEGACY -out "$TMP/identity.p12" \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -passout pass:atelier >/dev/null 2>&1

echo "Importing into your login keychain (you may be asked to authenticate)..."
security import "$TMP/identity.p12" -k "$LOGIN_KEYCHAIN" -P atelier \
  -T /usr/bin/codesign -T /usr/bin/security

# Trust the cert for code signing so find-identity reports it valid. Login-keychain
# scope avoids needing sudo / the System keychain.
security add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$TMP/cert.pem" 2>/dev/null || true

echo
if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
  echo "✓ Created '$IDENTITY_NAME'."
  echo "  Next: 'make run'. The first launch will ask for each protected folder"
  echo "  ONCE more, then macOS will remember. (The first build may also pop a"
  echo "  one-time keychain prompt — click 'Always Allow'.)"
else
  echo "! Identity not reported by find-identity. It may still work for signing;"
  echo "  run 'make run' and see. If signing fails, open Keychain Access and set"
  echo "  '$IDENTITY_NAME' to 'Always Trust' for Code Signing."
fi

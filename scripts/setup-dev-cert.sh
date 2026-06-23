#!/usr/bin/env bash
# Provision a stable, self-signed "Koifish Dev" code-signing identity in a
# DEDICATED keychain (not your login keychain). Signing dev builds with a stable
# identity keeps macOS TCC grants (Accessibility, Microphone) valid across
# rebuilds — ad-hoc signatures change hash on every build and silently lose them.
#
# Idempotent: re-running detects the existing identity and exits.
# To undo completely:  security delete-keychain "$HOME/Library/Keychains/koifish-codesign.keychain-db"
set -euo pipefail

IDENTITY="Koifish Dev"
KEYCHAIN="$HOME/Library/Keychains/koifish-codesign.keychain-db"
KC_PASS="koifish-dev"   # password for the dedicated keychain (local, low-stakes)

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> '$IDENTITY' identity already present — nothing to do."
    exit 0
fi

echo "==> Generating self-signed code-signing certificate '$IDENTITY'"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Koifish Dev
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -out "$TMP/id.p12" -passout pass:koifish >/dev/null 2>&1

echo "==> Creating dedicated keychain"
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"          # no auto-lock
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

echo "==> Importing identity (pre-authorizing codesign)"
security import "$TMP/id.p12" -k "$KEYCHAIN" -P koifish -A -T /usr/bin/codesign >/dev/null 2>&1
# Allow codesign to use the private key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1

echo "==> Adding keychain to the user search list (preserving existing)"
EXISTING="$(security list-keychains -d user | sed 's/[" ]//g')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo "==> Done. Identity available to codesign:"
security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY" || true
echo "    Build & sign with:  ./scripts/bundle.sh"

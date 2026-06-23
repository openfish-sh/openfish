#!/usr/bin/env bash
# Build Koifish and assemble a signed Koifish.app bundle.
#
# Usage: scripts/bundle.sh [debug|release]
#   debug   (default) - fast build, no optimization
#   release           - optimized build
#
# Produces ./Koifish.app in the repo root, ad-hoc code-signed with a stable
# identifier so macOS TCC (Accessibility / Microphone) grants survive rebuilds.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Display name is OpenFish; the executable + bundle id stay "Koifish" /
# "sh.koifish.Koifish" so TCC grants and Keychain keys carry over.
APP="OpenFish.app"
APP_ID="sh.koifish.Koifish"

echo "==> swift build ($CONFIG)"
# Release builds are universal (arm64 + x86_64) so the app runs on any Mac you
# hand it to; debug stays host-only for fast iteration.
if [[ "$CONFIG" == "release" ]]; then
    swift build -c "$CONFIG" --arch arm64 --arch x86_64
    BIN_PATH="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c "$CONFIG"
    BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Koifish" "$APP/Contents/MacOS/Koifish"
cp "scripts/Info.plist.template" "$APP/Contents/Info.plist"

# App icon: use a generated .icns if present, otherwise skip (app still runs).
if [[ -f "Resources/AppIcon.icns" ]]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    (no Resources/AppIcon.icns — run scripts/make_icon.sh to generate one)"
fi

# Prefer a stable self-signed identity so macOS TCC grants (Accessibility,
# Microphone) survive rebuilds. Falls back to ad-hoc if it isn't provisioned.
SIGN_IDENTITY="Koifish Dev"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    SIGN_ARG="$SIGN_IDENTITY"
    echo "==> Code-signing with stable identity '$SIGN_IDENTITY' (permissions persist across rebuilds)"
else
    SIGN_ARG="-"
    echo "==> Ad-hoc code-signing — run scripts/setup-dev-cert.sh once so permissions"
    echo "    survive rebuilds instead of breaking on every change."
fi

# A stable identifier keeps the TCC bundle identity constant across rebuilds.
codesign --force --deep \
    --sign "$SIGN_ARG" \
    --identifier "$APP_ID" \
    --entitlements "scripts/Koifish.entitlements" \
    --options runtime \
    "$APP" 2>/dev/null || \
codesign --force --deep \
    --sign "$SIGN_ARG" \
    --identifier "$APP_ID" \
    --entitlements "scripts/Koifish.entitlements" \
    "$APP"

echo "==> Done: $ROOT/$APP"
echo "    Launch with:  open ./$APP"
echo "    Logs:         log stream --predicate 'process == \"Koifish\"' --level debug"

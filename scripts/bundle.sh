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

# Display name is Openfish; the executable + bundle id stay "Koifish" /
# "sh.koifish.Koifish" so TCC grants and Keychain keys carry over.
APP="Openfish.app"
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

# Embed Sparkle.framework (auto-updates) and add the rpath so the binary finds it.
SPARKLE_FW=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FW" ]]; then
    mkdir -p "$APP/Contents/Frameworks"
    ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Koifish" 2>/dev/null || true
else
    echo "    (Sparkle.framework not found — run 'swift build' first so auto-updates work)"
fi

# Pick a signing identity:
#  - release: a "Developer ID Application" cert (distributable + notarizable), with a
#    secure timestamp. Falls back to the dev cert if none is installed.
#  - debug: the stable self-signed "Koifish Dev" so macOS TCC grants (Accessibility,
#    Microphone) survive rebuilds; ad-hoc if that cert isn't set up.
# Release signing identity: a personal (Ruben Flam) Developer ID Application cert.
# Set OPENFISH_SIGN_ID to choose explicitly. We don't auto-fall back to a company
# cert — a release without a Ruben Flam Developer ID stays on the dev cert (warned).
DEV_ID="${OPENFISH_SIGN_ID:-}"
if [[ -z "$DEV_ID" ]]; then
    DEV_ID=$(security find-identity -p codesigning -v 2>/dev/null \
        | grep "Developer ID Application" | grep -i "Ruben Flam" | head -1 \
        | sed -E 's/^[^"]*"([^"]*)".*/\1/')
fi
TIMESTAMP_ARG=""

if [[ "$CONFIG" == "release" && -n "$DEV_ID" ]]; then
    SIGN_ARG="$DEV_ID"
    TIMESTAMP_ARG="--timestamp"
    echo "==> Code-signing for release with '$DEV_ID' (hardened runtime + timestamp)"
elif security find-identity -p codesigning 2>/dev/null | grep -q "Koifish Dev"; then
    SIGN_ARG="Koifish Dev"
    echo "==> Code-signing with stable dev identity 'Koifish Dev' (grants persist across rebuilds)"
else
    SIGN_ARG="-"
    echo "==> Ad-hoc code-signing — run scripts/setup-dev-cert.sh once so permissions"
    echo "    survive rebuilds instead of breaking on every change."
fi

if [[ "$CONFIG" == "release" && -z "$DEV_ID" ]]; then
    echo "    (no 'Developer ID Application: Ruben Flam' cert — create one for team"
    echo "     B9H6A72DF8 or set OPENFISH_SIGN_ID; using dev cert.)"
fi

# Sign inside-out: Sparkle's helpers + framework first, then the app (no --deep,
# since the framework is already signed). A stable identifier keeps the TCC bundle
# identity constant across rebuilds.
SPARKLE_DIR="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_DIR" ]]; then
    for comp in \
        "Versions/B/XPCServices/Downloader.xpc" \
        "Versions/B/XPCServices/Installer.xpc" \
        "Versions/B/Autoupdate" \
        "Versions/B/Updater.app"; do
        [[ -e "$SPARKLE_DIR/$comp" ]] && \
            codesign --force --sign "$SIGN_ARG" --options runtime $TIMESTAMP_ARG "$SPARKLE_DIR/$comp"
    done
    codesign --force --sign "$SIGN_ARG" --options runtime $TIMESTAMP_ARG "$SPARKLE_DIR"
fi

codesign --force \
    --sign "$SIGN_ARG" \
    --identifier "$APP_ID" \
    --entitlements "scripts/Koifish.entitlements" \
    --options runtime $TIMESTAMP_ARG \
    "$APP"

if [[ "$CONFIG" == "release" && -n "$DEV_ID" ]]; then
    echo "    Next: ./scripts/notarize.sh  (notarize + staple, needs your Apple credentials)"
fi
echo "==> Done: $ROOT/$APP"
echo "    Launch with:  open ./$APP"
echo "    Logs:         log stream --predicate 'process == \"Koifish\"' --level debug"

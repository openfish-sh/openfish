#!/usr/bin/env bash
# Notarize and staple Openfish.dmg so a downloaded build opens with NO Gatekeeper
# warning. Requires a Developer ID-signed build (scripts/bundle.sh release).
#
# One-time credential setup (stored securely in your login keychain):
#   xcrun notarytool store-credentials openfish-notary \
#       --apple-id "you@example.com" \
#       --team-id  DVKGX6LQ53 \
#       --password "xxxx-xxxx-xxxx-xxxx"   # an app-specific password from appleid.apple.com
#
# Then, after building + packaging:
#   ./scripts/bundle.sh release && ./scripts/make_dmg.sh && ./scripts/notarize.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
DMG="$ROOT/Openfish.dmg"
PROFILE="${NOTARY_PROFILE:-openfish-notary}"

if [[ ! -f "$DMG" ]]; then
    echo "No $DMG — build + package first:  ./scripts/bundle.sh release && ./scripts/make_dmg.sh"
    exit 1
fi

echo "==> Submitting $DMG to Apple's notary service (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Stapling the notarization ticket…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "==> Done — $DMG is notarized and opens with no Gatekeeper prompt."

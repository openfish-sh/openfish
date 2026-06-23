#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from a 1024x1024 PNG.
# Usage: scripts/make_icon.sh [path/to/source.png]
#   default source: Resources/AppIcon-1024.png
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:-$ROOT/Resources/AppIcon-1024.png}"
OUT="$ROOT/Resources/AppIcon.icns"

if [[ ! -f "$SRC" ]]; then
    echo "Source PNG not found: $SRC"
    echo "Save the logo as Resources/AppIcon-1024.png (1024x1024) and re-run."
    exit 1
fi

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

# macOS icon set sizes (point size with @1x/@2x variants).
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
    px="${spec%%:*}"; name="${spec##*:}"
    sips -z "$px" "$px" "$SRC" --out "$ICONSET/icon_${name}.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT"
echo "==> Wrote $OUT"
echo "    Re-bundle to embed it:  ./scripts/bundle.sh"

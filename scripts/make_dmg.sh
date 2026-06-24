#!/usr/bin/env bash
# Package Openfish.app into a distributable Openfish.dmg (drag-to-Applications).
# Run after: scripts/bundle.sh release
#
# The DMG is what you attach to a GitHub Release; the Homebrew cask points at it.
# Not committed (it's in .gitignore alongside other *.dmg).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
APP="Openfish.app"
OUT="$ROOT/Openfish.dmg"

if [[ ! -d "$APP" ]]; then
    echo "Build it first:  ./scripts/bundle.sh release"
    exit 1
fi

STAGE="$(mktemp -d)/Openfish"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

rm -f "$OUT"
hdiutil create -volname "Openfish" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
rm -rf "$STAGE"

echo "==> Wrote $OUT"
echo "    sha256 (for the Homebrew cask):"
shasum -a 256 "$OUT" | awk '{print "    " $1}'

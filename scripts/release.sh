#!/usr/bin/env bash
# One-command release: bump version, build + notarize, publish the GitHub release,
# regenerate the Sparkle appcast, and bump the Homebrew cask.
#
# Usage:  ./scripts/release.sh <version>        e.g.  ./scripts/release.sh 0.1.3
#
# Prereqs (already set up): a Developer ID cert, a stored notarytool keychain
# profile (openfish-notary), the Sparkle EdDSA private key in the keychain, and
# `gh` authed with push access to the repo + tap.
set -euo pipefail

VERSION="${1:?usage: release.sh <version>  (e.g. 0.1.3)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REPO="openfish-sh/openfish"
TAP_URL="https://github.com/openfish-sh/homebrew-tap.git"
FEED_PREFIX="https://github.com/$REPO/releases/download/v$VERSION/"
APPCAST_BIN=".build/artifacts/sparkle/Sparkle/bin/generate_appcast"
IDENT="ruben--"
EMAIL="2705752+ruben--@users.noreply.github.com"

RELEASED=0
# If anything fails before we publish + commit, undo the in-tree version bump so a
# re-run doesn't double-increment the build number.
cleanup() {
    if [[ "$RELEASED" -eq 0 ]]; then
        echo "==> Release aborted before publish — reverting version bump." >&2
        git checkout -- scripts/Info.plist.template 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "==> Releasing $VERSION"

# 1. Bump CFBundleShortVersionString + integer CFBundleVersion.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" scripts/Info.plist.template) + 1 ))
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" \
                        -c "Set CFBundleVersion $BUILD" scripts/Info.plist.template

# 2. Build (universal, Developer ID), package, and notarize.
./scripts/bundle.sh release
./scripts/make_dmg.sh
./scripts/notarize.sh

# 3. Publish the GitHub release with the notarized DMG.
gh release create "v$VERSION" Openfish.dmg --repo "$REPO" \
    --title "Openfish $VERSION" --notes "Openfish $VERSION — notarized, auto-updates via Sparkle."

# 3b. Don't commit an appcast that points at an asset clients can't fetch yet —
# release-asset propagation can lag the API. Poll briefly before continuing.
echo "==> Verifying release asset is reachable…"
for i in 1 2 3 4 5 6; do
    curl -fsSI "${FEED_PREFIX}Openfish.dmg" >/dev/null 2>&1 && break
    [[ $i -eq 6 ]] && { echo "Release asset not reachable: ${FEED_PREFIX}Openfish.dmg" >&2; exit 1; }
    sleep 5
done

# 4. Regenerate the signed appcast pointing at this release's DMG. Seed the existing
# appcast so generate_appcast keeps prior versions instead of emitting a single entry.
STAGE="$(mktemp -d)"
cp Openfish.dmg "$STAGE/"
[[ -f appcast.xml ]] && cp appcast.xml "$STAGE/"
"$APPCAST_BIN" --download-url-prefix "$FEED_PREFIX" "$STAGE"
cp "$STAGE/appcast.xml" appcast.xml
rm -rf "$STAGE"

# 5. Commit the version bump + appcast.
git add scripts/Info.plist.template appcast.xml
git commit -q -m "Release $VERSION"
git push -q origin main
RELEASED=1   # published + committed — past the rollback window

# 6. Bump the Homebrew cask (version + post-staple sha256).
SHA=$(shasum -a 256 Openfish.dmg | awk '{print $1}')
TAPDIR="$(mktemp -d)/tap"
git clone -q "$TAP_URL" "$TAPDIR"
sed -i '' "s/version \"[^\"]*\"/version \"$VERSION\"/; s/sha256 \"[a-f0-9]*\"/sha256 \"$SHA\"/" \
    "$TAPDIR/Casks/openfish.rb"
# Fail loudly if either substitution didn't land, rather than pushing a stale cask.
grep -q "version \"$VERSION\"" "$TAPDIR/Casks/openfish.rb" || { echo "cask version bump failed" >&2; exit 1; }
grep -q "sha256 \"$SHA\"" "$TAPDIR/Casks/openfish.rb"       || { echo "cask sha256 bump failed" >&2; exit 1; }
git -C "$TAPDIR" -c user.email="$EMAIL" -c user.name="$IDENT" commit -qam "openfish $VERSION"
git -C "$TAPDIR" push -q origin main
rm -rf "$TAPDIR"

echo "==> Released $VERSION"
echo "    https://github.com/$REPO/releases/tag/v$VERSION"
echo "    Existing Sparkle clients will offer this on their next check."

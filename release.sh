#!/usr/bin/env bash
# Builds PDWatch.app, zips it, and publishes it as a GitHub Release.
#
#   ./release.sh 0.1.0
#
# Needs a clean working tree and the GitHub CLI (gh) logged in.
# The release tag (v0.1.0) is created on the current commit, which must
# already be pushed.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: $0 <version>, e.g. $0 0.1.0}"
TAG="v$VERSION"
ZIP="build/PDWatch-$VERSION.zip"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Commit or stash your changes first." >&2
    exit 1
fi
git fetch --quiet origin
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse '@{u}')" ]]; then
    echo "Push this branch first, so the release tag points at a published commit." >&2
    exit 1
fi

VERSION="$VERSION" ./build.sh
rm -f "$ZIP"
ditto -c -k --keepParent build/PDWatch.app "$ZIP"

gh release create "$TAG" "$ZIP" \
    --target "$(git rev-parse HEAD)" \
    --title "PDWatch $VERSION" \
    --notes "$(cat <<NOTES
Unzip and move **PDWatch.app** to /Applications.

The app is signed locally, not notarized by Apple, so macOS blocks the first
launch. Right-click the app and choose **Open**, or allow it under
System Settings → Privacy & Security.

Requires macOS 14 or later.
NOTES
)"
echo "Published $TAG with $ZIP."

#!/bin/sh
# Make a GitHub release of the version in Resources/Info.plist (CFBundleShortVersionString).
#
#   scripts/make-release.sh NOTES_FILE
#
# Builds the app, zips it as build/OpenDisplay-VERSION.zip, tags the current commit as vVERSION, pushes the tag,
# and creates the release on GitHub with the zip and the release notes in NOTES_FILE (markdown).
# Run it on a clean, pushed main branch.
set -eu
cd "$(dirname "$0")/.."

notes="${1:?usage: scripts/make-release.sh NOTES_FILE}"
version="$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
tag="v$version"

if [ -n "$(git status --porcelain)" ]; then
    echo "Commit your changes first." >&2
    exit 1
fi
git fetch -q origin main
if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
    echo "Push main first, and release from main." >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
    echo "$tag exists. Raise CFBundleShortVersionString (and CFBundleVersion) in Resources/Info.plist first." >&2
    exit 1
fi

./scripts/build-app.sh
zip="build/OpenDisplay-$version.zip"
rm -f "$zip"
# ditto keeps the code signature and the bundle structure (zip can break them).
ditto -c -k --keepParent build/OpenDisplay.app "$zip"

git tag -a "$tag" -m "OpenDisplay $version"
git push -q origin "$tag"
gh release create "$tag" "$zip" --title "OpenDisplay $version" --notes-file "$notes"

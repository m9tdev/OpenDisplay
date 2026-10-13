#!/bin/sh
# Start a release of the version in Resources/Info.plist (CFBundleShortVersionString).
#
#   scripts/make-release.sh NOTES_FILE
#
# Tags the current commit as vVERSION, with the release notes in NOTES_FILE (markdown) as the tag message, and
# pushes the tag. The Release workflow (.github/workflows/release.yml) then builds, signs, and notarizes the app on
# the runner, and publishes the GitHub release with the notes. Run it on a clean, pushed main branch.
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
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null || git ls-remote --exit-code --tags origin "$tag" > /dev/null; then
    echo "$tag exists. Raise CFBundleShortVersionString (and CFBundleVersion) in Resources/Info.plist first." >&2
    exit 1
fi

# verbatim: by default git removes lines that start with "#", which are markdown headings here. The message must end
# with a line break: else git cannot keep a tag signature apart from the last line.
message="$(mktemp)"
trap 'rm -f "$message"' EXIT
cat "$notes" > "$message"
[ -z "$(tail -c 1 "$message")" ] || echo >> "$message"
git tag -a "$tag" --cleanup=verbatim -F "$message"
git push -q origin "$tag"
echo "Pushed $tag. The Release workflow builds and publishes it:"
echo "https://github.com/m9tdev/OpenDisplay/actions/workflows/release.yml"

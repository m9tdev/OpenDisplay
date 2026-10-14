#!/bin/sh
# The app version, from version.txt (release-please keeps it up to date in its release pull request).
#
#   scripts/version.sh          the version, for example 0.2.0 (CFBundleShortVersionString)
#   scripts/version.sh build    the build number: MAJOR * 10000 + MINOR * 100 + PATCH, for example 200
#                               (CFBundleVersion). It goes up with each version, which Sparkle needs to find updates.
set -eu
cd "$(dirname "$0")/.."

version="$(tr -d '[:space:]' < version.txt)"
case "${1:-}" in
    "") echo "$version" ;;
    build)
        IFS=. read -r major minor patch <<EOV
$version
EOV
        if [ "$minor" -ge 100 ] || [ "$patch" -ge 100 ]; then
            echo "The build number needs MINOR and PATCH below 100, not $version." >&2
            exit 1
        fi
        echo $((major * 10000 + minor * 100 + patch))
        ;;
    *) echo "usage: scripts/version.sh [build]" >&2; exit 2 ;;
esac

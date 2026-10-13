#!/usr/bin/env bash
# Build OpenDisplay.app on Linux, sign it, and (with --notarize) notarize it. Needs nix-apple-dev
# (https://github.com/m9tdev/nix-apple-dev) with the iOS SDK set up: it has the macOS SDK too.
#
#   scripts/build-app-linux.sh             build, and sign with the Developer ID (else ad hoc)
#   scripts/build-app-linux.sh --notarize  also notarize with Apple, and staple the ticket to the app
#
# Signing: a "Developer ID Application" certificate as key.pem + cert.pem in DEVELOPER_ID_DIR
# (default ~/.config/omarchy-apple-dev/developer-id). Notarizing: an App Store Connect API key, from
# ~/.appstoreconnect/env (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH). Needs Nix with flakes.
# Output: build/OpenDisplay.app and build/OpenDisplay-VERSION.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

notarize=0
case "${1:-}" in
    --notarize) notarize=1 ;;
    "") ;;
    *) echo "usage: scripts/build-app-linux.sh [--notarize]" >&2; exit 2 ;;
esac

# apple-dev from the flake, built at the start, so the run uses one fixed version. Set APPLE_DEV to use another
# apple-dev, or APPLE_DEV_FLAKE for another flake (for example a local checkout).
apple_dev="${APPLE_DEV:-$(nix build --no-link --print-out-paths "${APPLE_DEV_FLAKE:-github:m9tdev/nix-apple-dev}")/bin/apple-dev}"
identity="${DEVELOPER_ID_DIR:-$HOME/.config/omarchy-apple-dev/developer-id}"
version="$(python3 -c 'import plistlib; print(plistlib.load(open("Resources/Info.plist", "rb"))["CFBundleShortVersionString"])')"

# SwiftBuild (the default build system) has no macOS platform in this SDK, so use the native one.
# Its linker warns for each file that its macOS support is experimental; the app works.
"$apple_dev" swift build -c release --build-system native --swift-sdk darwin --triple arm64-apple-macosx 2>&1 \
    | grep -v -e "does not support linking for platform macOS" -e "'--build-system native' has been deprecated"

app=build/OpenDisplay.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/OpenDisplay "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
# The compiled icon: the Linux actool cannot compile it for macOS yet (see scripts/make-app-icon.py).
cp Resources/AppIcon.compiled/Assets.car Resources/AppIcon.compiled/AppIcon.icns "$app/Contents/Resources/"

if [ -f "$identity/cert.pem" ] && [ -f "$identity/key.pem" ]; then
    # The hardened runtime and a secure timestamp: both are needed for notarization.
    "$apple_dev" rcodesign sign --pem-file "$identity/key.pem" --pem-file "$identity/cert.pem" \
        --code-signature-flags runtime "$app" > /dev/null
    echo "Signed with the Developer ID in $identity"
else
    [ "$notarize" = 0 ] || { echo "Notarizing needs a Developer ID: key.pem and cert.pem in $identity" >&2; exit 1; }
    "$apple_dev" rcodesign sign "$app" > /dev/null
    echo "Signed ad hoc (no Developer ID in $identity)"
fi

if [ "$notarize" = 1 ]; then
    set -a; . "$HOME/.appstoreconnect/env"; set +a
    key="$(mktemp)"
    trap 'rm -f "$key"' EXIT
    "$apple_dev" rcodesign encode-app-store-connect-api-key -o "$key" "$ASC_ISSUER_ID" "$ASC_KEY_ID" "$ASC_KEY_PATH" > /dev/null
    # Uploads the app, waits for Apple's result, and staples the ticket to the app.
    "$apple_dev" rcodesign notary-submit --api-key-file "$key" --staple "$app"
fi

# A zip that keeps the file modes (the executable bit), like ditto on a Mac.
zip="build/OpenDisplay-$version.zip"
python3 - "$app" "$zip" <<'PY'
import os, sys, zipfile
app, out = sys.argv[1], sys.argv[2]
base = os.path.dirname(app)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(app):
        for name in sorted(dirs) + sorted(files):
            path = os.path.join(root, name)
            info = zipfile.ZipInfo.from_file(path, os.path.relpath(path, base))
            if os.path.isdir(path):
                z.writestr(info, "")
            else:
                info.compress_type = zipfile.ZIP_DEFLATED
                with open(path, "rb") as f:
                    z.writestr(info, f.read())
PY
echo "Built $app and $zip"

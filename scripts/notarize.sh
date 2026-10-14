#!/bin/sh
# Notarize build/OpenDisplay.app with Apple, staple the ticket to it, and zip it as build/OpenDisplay-VERSION.zip.
# Run scripts/build-app.sh with SIGN_IDENTITY set to the Developer ID first. Needs a Mac (notarytool, stapler, ditto).
#
# The App Store Connect API key comes from the environment: ASC_KEY_ID, ASC_ISSUER_ID, and the key itself in
# ASC_KEY_P8 (for example GitHub secrets), or the path of the .p8 file in ASC_KEY_PATH.
set -eu
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?ASC_KEY_ID is not set}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set}"
app=build/OpenDisplay.app
version="$(scripts/version.sh)"
zip="build/OpenDisplay-$version.zip"

secrets="$(mktemp -d)"
trap 'rm -rf "$secrets"' EXIT
if [ -n "${ASC_KEY_P8:-}" ]; then
    ASC_KEY_PATH="$secrets/AuthKey.p8"
    (umask 077 && printf '%s\n' "$ASC_KEY_P8" > "$ASC_KEY_PATH")
fi
: "${ASC_KEY_PATH:?Set ASC_KEY_P8 or ASC_KEY_PATH}"

# Apple needs a zip of the app. ditto keeps the code signature and the bundle structure (zip can break them).
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
# Waits for Apple's result (usually a few minutes). Fails when Apple does not accept the app.
xcrun notarytool submit "$zip" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait --timeout 30m
# Staple the ticket to the app, so it opens without a network check, then zip it again with the ticket.
xcrun stapler staple "$app"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
echo "Notarized $app and made $zip"

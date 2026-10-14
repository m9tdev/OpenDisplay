#!/bin/sh
# Build "OpenDisplay.app" into ./build. Pass --install to copy it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
app="build/OpenDisplay.app"
rm -rf "$app"
bin="$(swift build -c release --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/OpenDisplay" "$app/Contents/MacOS/"
# Sparkle (automatic updates). ditto keeps the symlinks of the framework. The XPC services are only for sandboxed
# apps, so leave them out: less code to sign.
ditto "$bin/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
rm -rf "$app/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" "$app/Contents/Frameworks/Sparkle.framework/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/OpenDisplay"
cp Resources/Info.plist "$app/Contents/"
# The version comes from version.txt (release-please updates it), not from the Info.plist in the repository.
plutil -replace CFBundleShortVersionString -string "$(scripts/version.sh)" "$app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(scripts/version.sh build)" "$app/Contents/Info.plist"
# The icon is an Icon Composer document (scripts/make-app-icon.py makes it). actool makes Assets.car (Liquid Glass,
# macOS 26 and later) and AppIcon.icns (earlier versions). actool needs absolute paths.
xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$PWD/$app/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "$(mktemp)" > /dev/null
# Sign with a stable certificate if there is one, so macOS keeps permissions (Accessibility) after a rebuild.
# Set SIGN_IDENTITY to choose one. Without a certificate, sign ad hoc.
# For a release, SIGN_IDENTITY is the Developer ID: then also sign with the hardened runtime and a secure timestamp,
# which notarization needs (see scripts/notarize.sh).
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
case "$identity" in
    "Developer ID Application:"*) sign() { codesign --force --options runtime --timestamp --sign "$identity" "$@"; } ;;
    *) sign() { codesign --force --sign "${identity:--}" "$@"; } ;;
esac
# From the inside out: Sparkle's helper programs, then the framework, then the app.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
sign "$sparkle/Versions/B/Autoupdate"
sign "$sparkle/Versions/B/Updater.app"
sign "$sparkle"
sign "$app"
echo "Built $app (signed: ${identity:-ad hoc})"

if [ "${1:-}" = "--install" ]; then
    mkdir -p ~/Applications
    pkill -x OpenDisplay || true
    # Wait until it has quit, or macOS cannot open the new copy.
    while pgrep -x OpenDisplay > /dev/null; do sleep 0.1; done
    rm -rf ~/Applications/"OpenDisplay.app"
    cp -R "$app" ~/Applications/
    open ~/Applications/"OpenDisplay.app"
    echo "Installed to ~/Applications"
fi

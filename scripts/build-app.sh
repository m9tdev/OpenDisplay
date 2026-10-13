#!/bin/sh
# Build "OpenDisplay.app" into ./build. Pass --install to copy it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
app="build/OpenDisplay.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/OpenDisplay" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
# The compiled app icon: Assets.car (Liquid Glass, macOS 26 and later) and AppIcon.icns (earlier versions).
# They are in the repository, so builds without Apple's actool (on Linux) get the same icon.
# scripts/make-app-icon.py makes them from Resources/AppIcon.icon.
cp Resources/AppIcon.compiled/Assets.car Resources/AppIcon.compiled/AppIcon.icns "$app/Contents/Resources/"
# Sign with a stable certificate if there is one, so macOS keeps permissions (Accessibility) after a rebuild.
# Set SIGN_IDENTITY to choose one. Without a certificate, sign ad hoc.
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${identity:--}" "$app"
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

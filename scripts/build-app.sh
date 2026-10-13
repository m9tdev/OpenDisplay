#!/bin/sh
# Build "Better Monitor.app" into ./build. Pass --install to copy it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
app="build/Better Monitor.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/BetterMonitor" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
# Sign with a stable certificate if there is one, so macOS keeps permissions (Accessibility) after a rebuild.
# Set SIGN_IDENTITY to choose one. Without a certificate, sign ad hoc.
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
codesign --force --sign "${identity:--}" "$app"
echo "Built $app (signed: ${identity:-ad hoc})"

if [ "${1:-}" = "--install" ]; then
    mkdir -p ~/Applications
    pkill -x BetterMonitor || true
    rm -rf ~/Applications/"Better Monitor.app"
    cp -R "$app" ~/Applications/
    open ~/Applications/"Better Monitor.app"
    echo "Installed to ~/Applications"
fi

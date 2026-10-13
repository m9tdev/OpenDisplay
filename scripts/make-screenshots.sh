#!/bin/sh
# Make the README screenshots in assets/screenshots: the menu (short, and with all controls of the external
# display) and the Settings window, in light and dark mode.
#
# It builds the app, opens the menu and the Settings window several times, and captures them. It takes about
# 30 seconds: don't use the mouse or keyboard while it runs. Afterwards, it restores your OpenDisplay settings and
# opens the installed app again.
#
# Needs an external display (for the controls in the expanded menu), and Pillow (pip3 install pillow).
# The presets in the Settings screenshots are your own presets.
set -eu
cd "$(dirname "$0")/.."

./scripts/build-app.sh > /dev/null
app="$PWD/build/OpenDisplay.app"
out="$PWD/assets/screenshots"
tmp="$(mktemp -d)"
helper="$tmp/screenshot-helper"
swiftc -O scripts/screenshot-helper.swift -o "$helper"
mkdir -p "$out"

external="$("$helper" external-key)" || { echo "Connect an external display first." >&2; exit 1; }
scale="$("$helper" scale)"

quit() {
    pkill -x OpenDisplay || true
    while pgrep -x OpenDisplay > /dev/null; do sleep 0.1; done
}

# Keep the user's settings, so the expanded menu below does not change them.
quit
defaults export dev.m9t.OpenDisplay "$tmp/settings.plist"
restore() {
    quit
    defaults import dev.m9t.OpenDisplay "$tmp/settings.plist"
    open ~/Applications/OpenDisplay.app 2> /dev/null || true
    rm -rf "$tmp"
}
trap restore EXIT

# menu NAME APPEARANCE EXPANDED
menu() {
    quit
    if [ "$3" = yes ]; then
        defaults write dev.m9t.OpenDisplay expandedDisplays -array "$external"
    else
        defaults write dev.m9t.OpenDisplay expandedDisplays -array
    fi
    # Away from the menu, so no row shows a hover highlight.
    "$helper" warp
    # The menu is glass: the backdrop gives it a plain light or dark color behind it.
    open "$app" --args --appearance "$2" --backdrop --open-menu 2
    sleep 4
    set -- "$1" "$2" $("$helper" window 101)
    x=$3 y=$4 w=$5 h=$6
    # The area around the menu, over the backdrop. cutout-menu.py removes the backdrop.
    screencapture -x -R "$((x - 40)),$((y - 30)),$((w + 80)),$((h + 70))" "$tmp/$1.png"
    [ "$2" = dark ] && dark=1 || dark=0
    python3 scripts/cutout-menu.py "$tmp/$1.png" "$out/$1.png" "$scale" "$dark"
    echo "Made $1.png"
}

# settings NAME APPEARANCE
settings() {
    quit
    "$helper" warp
    open "$app" --args --appearance "$2" --open-settings
    sleep 4
    set -- "$1" "$2" $("$helper" window 0)
    # A window capture, with the system margins and shadow.
    screencapture -x -l "$7" "$out/$1.png"
    echo "Made $1.png"
}

menu menu-light light no
menu menu-expanded-light light yes
settings settings-light light
menu menu-dark dark no
menu menu-expanded-dark dark yes
settings settings-dark dark

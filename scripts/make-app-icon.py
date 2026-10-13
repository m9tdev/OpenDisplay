#!/usr/bin/env python3
"""Make Resources/AppIcon.icon (an Icon Composer document) from the geometry of MenuBarIcon.swift.

The app icon and the menu bar icon have the same shape: the menu bar icon in points, scaled up so the
screen is 720 pt wide on the 1024 pt canvas. If you change the geometry here, change MenuBarIcon.swift too.
scripts/build-app.sh compiles the icon with Apple's actool.
"""
import json
import math
import os
import shutil

ICON = os.path.join(os.path.dirname(__file__), "..", "Resources", "AppIcon.icon")


def p3(r, g, b, a=1.0):
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


def gradient(top, bottom):
    return {"linear-gradient": [top, bottom], "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def rounded_rect(x, y, w, h, r):
    return (f"M{x+r:.2f} {y:.2f} H{x+w-r:.2f} A{r:.2f} {r:.2f} 0 0 1 {x+w:.2f} {y+r:.2f} V{y+h-r:.2f} "
            f"A{r:.2f} {r:.2f} 0 0 1 {x+w-r:.2f} {y+h:.2f} H{x+r:.2f} A{r:.2f} {r:.2f} 0 0 1 {x:.2f} {y+h-r:.2f} "
            f"V{y+r:.2f} A{r:.2f} {r:.2f} 0 0 1 {x+r:.2f} {y:.2f} Z")


def circle(cx, cy, r):
    return f"M{cx-r:.2f} {cy:.2f} A{r:.2f} {r:.2f} 0 1 0 {cx+r:.2f} {cy:.2f} A{r:.2f} {r:.2f} 0 1 0 {cx-r:.2f} {cy:.2f} Z"


def ray(cx, cy, angle, r1, r2, width):
    """A line from r1 to r2 from the center, with round ends, like a stroke with round caps."""
    ux, uy = math.cos(angle), math.sin(angle)
    nx, ny = -uy * width / 2, ux * width / 2
    a, b = (cx + ux * r1 + nx, cy + uy * r1 + ny), (cx + ux * r2 + nx, cy + uy * r2 + ny)
    c, d = (cx + ux * r2 - nx, cy + uy * r2 - ny), (cx + ux * r1 - nx, cy + uy * r1 - ny)
    h = width / 2
    return (f"M{a[0]:.2f} {a[1]:.2f} L{b[0]:.2f} {b[1]:.2f} A{h:.2f} {h:.2f} 0 0 0 {c[0]:.2f} {c[1]:.2f} "
            f"L{d[0]:.2f} {d[1]:.2f} A{h:.2f} {h:.2f} 0 0 0 {a[0]:.2f} {a[1]:.2f} Z")


def svg(body):
    return f'<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">\n{body}\n</svg>\n'


# The geometry of MenuBarIcon.swift, in points (a 20 × 16 pt image).
LINE, RADIUS = 1.25, 1.6
SCREEN = (0.75, 0.5, 18.5, 12.5)  # x, y, width, height
SUN_RADIUS, RAY_START, RAY_END, RAY_WIDTH = 1.5, 2.55, 3.45, 1.0
NECK = (8.7, 11.3, 8.4, 11.6, 15)  # top left, top right, bottom left, bottom right, bottom
FOOT = (6, 8)  # x, width; it ends at 16 pt and is LINE thick

# Scale up so the screen is 720 pt wide, and center the drawing (15.5 pt high) on the canvas.
k = 720 / SCREEN[2]
X = lambda x: 152 + (x - SCREEN[0]) * k
Y = lambda y: (1024 - 15.5 * k) / 2 + (y - SCREEN[1]) * k

sx, sy, sw, sh = SCREEN
outer = rounded_rect(X(sx), Y(sy), sw * k, sh * k, RADIUS * k)
inner = rounded_rect(X(sx + LINE), Y(sy + LINE), (sw - 2 * LINE) * k, (sh - 2 * LINE) * k, max(RADIUS - LINE, 0.05) * k)
cx, cy = X(sx + sw / 2), Y(sy + sh / 2)
sun = " ".join([circle(cx, cy, SUN_RADIUS * k)] +
               [ray(cx, cy, i * math.pi / 4, RAY_START * k, RAY_END * k, RAY_WIDTH * k) for i in range(8)])
tl, tr, bl, br, bottom = NECK
neck = f"M{X(tl):.2f} {Y(sy + sh - 0.5):.2f} H{X(tr):.2f} L{X(br):.2f} {Y(bottom):.2f} H{X(bl):.2f} Z"
foot = rounded_rect(X(FOOT[0]), Y(16 - LINE), FOOT[1] * k, LINE * k, LINE / 2 * k)

# Front: the bezel with the sun in its opening (even-odd fill), so one gradient goes over both.
screen = f'<path d="{outer} {inner} {sun}" fill="white" fill-rule="evenodd"/>'
# Back: the whole display in see-through glass, so the stand is an even tint of the background.
display = screen + f'\n<path d="{neck} {foot}" fill="white"/>'

orange = gradient(p3(0.98, 0.62, 0.20), p3(0.92, 0.30, 0.18))
document = {
    "fill": orange,
    "groups": [
        {
            "layers": [{"image-name": "screen.svg", "name": "screen", "fill": gradient(p3(1, 1, 1), p3(1.0, 0.84, 0.70))}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.05},
        },
        {
            "layers": [{"image-name": "display.svg", "name": "display"}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": True, "value": 0.6},
        },
    ],
    "supported-platforms": {"squares": ["macOS"]},
}

shutil.rmtree(ICON, ignore_errors=True)
os.makedirs(os.path.join(ICON, "Assets"))
open(os.path.join(ICON, "Assets", "screen.svg"), "w").write(svg(screen))
open(os.path.join(ICON, "Assets", "display.svg"), "w").write(svg(display))
with open(os.path.join(ICON, "icon.json"), "w") as f:
    json.dump(document, f, indent=2)
print("Made", os.path.normpath(ICON))

